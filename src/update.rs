use std::fs;
use std::io::{IsTerminal, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::util::{download, env, expand_tilde, is_url};
use crate::VERSION;

/**
 * gits --update: the binary replaces itself with a release from GitHub.
 * The rules are described in submodules/xx/UPDATE_IMPLEMENTATION.md:
 * all or nothing, nothing is trusted before it is verified, no new dependencies
 * (curl / wget and sha256sum / shasum as subprocesses), testable with a local directory.
 */
pub const RELEASES: &str = "https://github.com/stopsopa/gits/releases";
pub const ENV_RELEASES: &str = "GITS_RELEASES";
pub const ENV_CONFIRM: &str = "GITS_CONFIRM";
// tests: the answer to the confirmation, instead of the keyboard
const ENV_TEST_ANSWER: &str = "GITS_TEST_ANSWER";

const SUMS: &str = "SHA256SUMS.txt";

/**
 * Name of the binary of this platform among files of a release.
 * Known at compile time: the binary which is running is the best proof of what works here.
 * The same names are used by .github/workflows/rust.yml.
 */
pub fn asset() -> Option<&'static str> {
    if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        Some("gits-darwin-arm64")
    } else if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        Some("gits-linux-x64")
    } else if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
        Some("gits-linux-arm64")
    } else {
        None
    }
}

// url or local directory ("~/" expanded), without "/" at the end
pub fn releases() -> String {
    let source = env(ENV_RELEASES).unwrap_or_else(|| RELEASES.to_string());
    let source = if is_url(&source) {
        source
    } else {
        expand_tilde(&source).to_string_lossy().to_string()
    };
    source.trim_end_matches('/').to_string()
}

// tag goes to urls and paths, nothing surprising is allowed in it
pub fn valid_tag(tag: &str) -> bool {
    !tag.is_empty()
        && tag.len() <= 64
        && !tag.starts_with(['.', '-'])
        && tag
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-' || b == b'_')
}

// "https://github.com/stopsopa/gits/releases/tag/v0.1.0" -> "v0.1.0"
pub fn tag_from_redirect(location: &str) -> Option<String> {
    let tag = location.trim().rsplit_once("/tag/")?.1;
    let tag = tag.split(['?', '#', '/']).next()?;
    valid_tag(tag).then(|| tag.to_string())
}

// sha256 of the file `name` from the content of SHA256SUMS.txt ("<sha256>  <name>", name may start with *)
pub fn sum_for(sums: &str, name: &str) -> Option<String> {
    sums.lines().find_map(|line| {
        let mut parts = line.split_whitespace();
        let hash = parts.next()?;
        let file = parts.next()?;
        let file = file.strip_prefix('*').unwrap_or(file);
        (file == name && hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_hexdigit()))
            .then(|| hash.to_ascii_lowercase())
    })
}

fn output_of(program: &str, args: &[&str]) -> Option<(bool, String, String)> {
    let out = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()?;
    Some((
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).to_string(),
        String::from_utf8_lossy(&out.stderr).to_string(),
    ))
}

/**
 * url:   <releases>/latest redirects to <releases>/tag/<tag>, only the target of the redirect is
 *        read (no API: no rate limit, no token, no JSON)
 * local: file <releases>/latest contains the tag
 */
fn latest_tag(releases: &str) -> Result<String, String> {
    let fail = |got: &str| {
        format!(
            "can't find out the latest release from >{releases}/latest< (no network? no release published yet?), got >{}<",
            got.trim()
        )
    };

    if !is_url(releases) {
        let file = format!("{releases}/latest");
        let tag = fs::read_to_string(&file).map_err(|e| fail(&e.to_string()))?;
        let tag = tag.trim();
        return valid_tag(tag)
            .then(|| tag.to_string())
            .ok_or_else(|| fail(tag));
    }

    let url = format!("{releases}/latest");
    let location = match output_of(
        "curl",
        &["-sS", "-o", "/dev/null", "-w", "%{redirect_url}", &url],
    ) {
        Some((_, stdout, _)) => stdout,
        None => match output_of("wget", &["--max-redirect=0", "-S", "-O", "/dev/null", &url]) {
            Some((_, _, stderr)) => stderr
                .lines()
                .find_map(|l| {
                    l.trim()
                        .strip_prefix("Location:")
                        .map(|v| v.trim().to_string())
                })
                .unwrap_or_default(),
            None => {
                return Err(
                    "neither curl nor wget found, one of them is needed for --update".to_string(),
                )
            }
        },
    };
    tag_from_redirect(&location).ok_or_else(|| fail(&location))
}

fn release_file(releases: &str, tag: &str, file: &str) -> Result<Vec<u8>, String> {
    let location = format!("{releases}/download/{tag}/{file}");
    let content = if is_url(releases) {
        download(&location)
    } else {
        fs::read(&location).map_err(|e| format!("can't read >{location}<: {e}"))
    };
    match content {
        Ok(c) if !c.is_empty() => Ok(c),
        Ok(_) => Err(format!(
            ">{location}< is empty, is >{tag}< a published release with all files?"
        )),
        Err(e) => Err(format!(
            "{e}\n  is >{tag}< a published release with all files?"
        )),
    }
}

fn sha256(file: &Path) -> Result<String, String> {
    let path = file.to_string_lossy().to_string();
    for (program, args) in [
        ("sha256sum", vec![path.as_str()]),
        ("shasum", vec!["-a", "256", path.as_str()]),
    ] {
        if let Some((true, stdout, _)) = output_of(program, &args) {
            if let Some(hash) = stdout.split_whitespace().next() {
                return Ok(hash.to_ascii_lowercase());
            }
        }
    }
    Err("neither sha256sum nor shasum found, one of them is needed for --update".to_string())
}

// the binary is really executed: a checksum doesn't prove that it runs on this machine
fn reports(binary: &Path, tag: &str) -> Result<(), String> {
    let expected = format!("gits {tag}");
    let out = Command::new(binary)
        .arg("--version")
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!(">{}< can't be executed: {e}", binary.display()))?;
    let got = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if out.status.success() && got == expected {
        Ok(())
    } else {
        Err(format!(
            ">{} --version< should print >{expected}<, it printed >{got}< ({})",
            binary.display(),
            out.status
        ))
    }
}

fn confirmed(installed: &Path) -> Result<bool, String> {
    if env(ENV_CONFIRM).as_deref() == Some("false") {
        return Ok(true);
    }
    let answer = match env(ENV_TEST_ANSWER) {
        Some(a) => a,
        None => {
            if !std::io::stdin().is_terminal() {
                return Err(format!(
                    "replacing >{}< needs confirmation and there is no terminal, use {ENV_CONFIRM}=false",
                    installed.display()
                ));
            }
            print!("Replace it? [Y/n] ");
            let _ = std::io::stdout().flush();
            let mut line = String::new();
            std::io::stdin()
                .read_line(&mut line)
                .map_err(|e| format!("can't read the answer: {e}"))?;
            line
        }
    };
    let answer = answer.trim().to_ascii_lowercase();
    Ok(answer.is_empty() || answer == "y" || answer == "yes")
}

const USAGE: &str = "usage:
  gits --update            update to the latest release
  gits --update <tag>      install the given release (also an older one), e.g. v0.1.0
  gits --update --check    only say whether there is something newer, change nothing";

pub fn run(args: &[String]) -> Result<i32, String> {
    let (check, requested) = match args {
        [] => (false, None),
        [flag] if flag == "--check" => (true, None),
        [tag] if valid_tag(tag) => (false, Some(tag.clone())),
        _ => return Err(USAGE.to_string()),
    };

    if VERSION == "dev" {
        return Err(
            "this binary is a local build (version dev), not a release: there is nothing to compare it with, it can't update itself"
                .to_string(),
        );
    }
    let asset =
        asset().ok_or_else(|| "there are no released binaries for this platform".to_string())?;
    let releases = releases();

    println!("installed: {VERSION}");
    let tag = match requested {
        Some(tag) => {
            println!("requested: {tag}");
            tag
        }
        None => {
            let tag = latest_tag(&releases)?;
            println!("latest: {tag}");
            tag
        }
    };

    // equality, not "newer than": that is what makes installing an older release possible
    if tag == VERSION {
        println!("gits is up to date");
        return Ok(0);
    }
    if check {
        println!("to install it: gits --update");
        return Ok(0);
    }

    // gits can be started through a symlink, the real file is the one to replace
    let installed = std::env::current_exe()
        .and_then(fs::canonicalize)
        .map_err(|e| format!("can't find the file of the running binary: {e}"))?;
    println!("files to replace:\n  {}", installed.display());

    if !confirmed(&installed)? {
        println!("nothing changed");
        return Ok(0);
    }

    // next to the installed file: rename is atomic only inside one filesystem
    let pid = std::process::id();
    let with_suffix = |suffix: &str| {
        let mut name = installed.as_os_str().to_os_string();
        name.push(format!(".{suffix}-{pid}"));
        PathBuf::from(name)
    };
    let new = with_suffix("new");
    let old = with_suffix("old");

    let result = install(&releases, &tag, asset, &installed, &new, &old);

    // whatever happened
    let _ = fs::remove_file(&new);
    let _ = fs::remove_file(&old);

    result?;
    println!("gits updated: {VERSION} -> {tag}");
    Ok(0)
}

// the installed file is not touched before everything about the new one is verified
fn install(
    releases: &str,
    tag: &str,
    asset: &str,
    installed: &Path,
    new: &Path,
    old: &Path,
) -> Result<(), String> {
    println!("downloading {SUMS}");
    let sums = release_file(releases, tag, SUMS)?;
    let expected = sum_for(&String::from_utf8_lossy(&sums), asset)
        .ok_or_else(|| format!("there is no checksum of >{asset}< in {SUMS} of release >{tag}<"))?;

    println!("downloading {asset}");
    let binary = release_file(releases, tag, asset)?;
    fs::write(new, binary)
        .and_then(|_| fs::set_permissions(new, fs::Permissions::from_mode(0o755)))
        .map_err(|e| {
            format!(
                "can't write >{}<: {e} (the directory has to be writable for the update)",
                new.display()
            )
        })?;

    if sha256(new)? != expected {
        return Err(format!(
            "checksum of downloaded >{asset}< doesn't match {SUMS}, nothing was changed"
        ));
    }
    println!("checksum ok: {asset}");

    reports(new, tag)
        .map_err(|e| format!("downloaded binary doesn't work here, nothing was changed: {e}"))?;
    println!("test ok: downloaded binary reports gits {tag}");

    fs::copy(installed, old)
        .map_err(|e| format!("can't make a copy of >{}<: {e}", installed.display()))?;
    // rename, never write into the installed file: it is the executable which is running right now
    fs::rename(new, installed)
        .map_err(|e| format!("can't replace >{}<: {e}", installed.display()))?;

    if let Err(e) = reports(installed, tag) {
        return match fs::rename(old, installed) {
            Ok(()) => Err(format!("installed binary doesn't work, the previous one was restored: {e}")),
            Err(restore) => Err(format!(
                "installed binary doesn't work AND THE PREVIOUS ONE COULD NOT BE RESTORED ({restore}): {e}\n  install it by hand from {releases}"
            )),
        };
    }
    println!("test ok: installed binary reports gits {tag}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tags() {
        assert!(valid_tag("v0.1.0"));
        assert!(valid_tag("1.2.3-rc_1"));
        for bad in ["", "--check", "../v1", "..", "v1 2", "-v1", ".v1", "v1/2"] {
            assert!(!valid_tag(bad), "{bad}");
        }
        assert!(!valid_tag(&"v".repeat(65)));
    }

    #[test]
    fn redirect() {
        assert_eq!(
            tag_from_redirect("https://github.com/stopsopa/gits/releases/tag/v0.1.0").as_deref(),
            Some("v0.1.0")
        );
        assert_eq!(
            tag_from_redirect("https://github.com/stopsopa/gits/releases/tag/v0.1.0?x=1\n")
                .as_deref(),
            Some("v0.1.0")
        );
        // repository without a release
        assert_eq!(
            tag_from_redirect("https://github.com/stopsopa/gits/releases"),
            None
        );
        assert_eq!(tag_from_redirect(""), None);
    }

    #[test]
    fn sums() {
        let hash = "A".repeat(64);
        let text = format!(
            "{hash}  gits-linux-x64\n{}  *gits-darwin-arm64\nshort  gits-linux-arm64\n",
            "b".repeat(64)
        );
        assert_eq!(sum_for(&text, "gits-linux-x64"), Some("a".repeat(64)));
        assert_eq!(sum_for(&text, "gits-darwin-arm64"), Some("b".repeat(64)));
        assert_eq!(sum_for(&text, "gits-linux-arm64"), None);
        assert_eq!(sum_for(&text, "unknown"), None);
    }
}
