use crate::cli::{cli, Options};
use std::fs;
use std::io::{IsTerminal, Read};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_signal(_: libc::c_int) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

/**
 * Ctrl+C must not kill gits before the temporary clone is removed. The handler only sets a flag:
 * git (the child, same process group) gets the signal too and ends, gits sees the failure,
 * returns through the normal error path and the directory is removed on the way out.
 */
pub fn install_signal_handlers() {
    let handler = on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t;
    unsafe {
        libc::signal(libc::SIGINT, handler);
        libc::signal(libc::SIGTERM, handler);
    }
}

pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::SeqCst)
}

fn colors() -> bool {
    std::env::var_os("NO_COLOR").is_none() && std::io::stdout().is_terminal()
}

fn paint(code: &str, text: &str) -> String {
    if colors() {
        format!("\x1b[{code}m{text}\x1b[0m")
    } else {
        text.to_string()
    }
}

pub fn green(text: &str) -> String {
    paint("32", text)
}

pub fn red(text: &str) -> String {
    paint("31", text)
}

pub fn yellow(text: &str) -> String {
    paint("33", text)
}

pub fn home() -> Option<PathBuf> {
    match std::env::var_os("HOME") {
        Some(h) if !h.is_empty() => Some(PathBuf::from(h)),
        _ => None,
    }
}

// "~/x" -> "<home>/x", everything else untouched
pub fn expand_tilde(path: &str) -> PathBuf {
    if path == "~" {
        if let Some(h) = home() {
            return h;
        }
    }
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(h) = home() {
            return h.join(rest);
        }
    }
    PathBuf::from(path)
}

// env var, where empty means not defined
pub fn env(name: &str) -> Option<String> {
    match std::env::var(name) {
        Ok(v) if !v.trim().is_empty() => Some(v.trim().to_string()),
        _ => None,
    }
}

/**
 * Until the rename every variable of gits started with GITSTORAGE (GITSTORAGESOURCE, ...).
 * The old names are still read when the new one is not defined: nobody has to change
 * ~/.zshrc and every .git/gits.sh on the same day.
 */
pub const OLD_NAMES: [(&str, &str); 6] = [
    ("GITS_SOURCE", "GITSTORAGESOURCE"),
    ("GITS_SHELL", "GITSTORAGETESHELL"),
    ("GITS_ENCRYPTION_SOCKET", "GITSTORAGETENCRYPTIONSOCKET"),
    ("GITS_TEMPLATE", "GITSTORAGETEMPLATE"),
    ("GITS_TARGETDIR", "GITSTORAGETARGETDIR"),
    ("GITS_LIST", "GITSTORAGELIST"),
];

pub fn old_name(name: &str) -> Option<&'static str> {
    OLD_NAMES
        .iter()
        .find(|(new, _)| *new == name)
        .map(|(_, old)| *old)
}

// env var by its new name, else by its old one. The second value: the name it was found under
pub fn env_named(name: &str) -> Option<(String, String)> {
    if let Some(value) = env(name) {
        return Some((value, name.to_string()));
    }
    let old = old_name(name)?;
    env(old).map(|value| (value, old.to_string()))
}

pub fn env_any(name: &str) -> Option<String> {
    env_named(name).map(|(value, _)| value)
}

pub fn random_hex(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    let ok = fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut buf))
        .is_ok();
    if !ok {
        // good enough for a directory name which is checked for existence anyway
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let mut seed = nanos ^ ((std::process::id() as u128) << 32);
        for b in buf.iter_mut() {
            seed = seed
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            *b = (seed >> 40) as u8;
        }
    }
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/**
 * Path next to `file` which doesn't exist: "<file>.hash<8 hex>".
 * For files which exist only for a moment (plain copy before encryption, decrypted copy).
 */
pub fn unique_sibling(file: &Path) -> PathBuf {
    loop {
        let mut name = file.as_os_str().to_os_string();
        name.push(format!(".hash{}", random_hex(4)));
        let candidate = PathBuf::from(name);
        if fs::symlink_metadata(&candidate).is_err() {
            return candidate;
        }
    }
}

// path made absolute and without "." and "..", the file doesn't have to exist (no symlinks resolved)
pub fn absolute(path: &Path, base: &Path) -> PathBuf {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        base.join(path)
    };
    let mut out = PathBuf::new();
    for c in joined.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

// path of `file` as seen from directory `from`, both absolute and normalized
pub fn relative(file: &Path, from: &Path) -> PathBuf {
    let f: Vec<Component> = file.components().collect();
    let d: Vec<Component> = from.components().collect();
    let mut common = 0;
    while common < f.len() && common < d.len() && f[common] == d[common] {
        common += 1;
    }
    let mut out = PathBuf::new();
    for _ in common..d.len() {
        out.push("..");
    }
    for c in &f[common..] {
        out.push(c.as_os_str());
    }
    out
}

pub fn copy_file(from: &Path, to: &Path) -> Result<(), String> {
    if let Some(parent) = to.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("can't create directory >{}<: {e}", parent.display()))?;
    }
    fs::copy(from, to)
        .map(|_| ())
        .map_err(|e| format!("can't copy >{}< to >{}<: {e}", from.display(), to.display()))
}

/**
 * git with output passed through to the user while it flows.
 * quiet: stdout dropped, stderr stays (errors are always worth seeing).
 *
 * git doesn't write to the terminal directly (see cli.rs), so it would never use colors by
 * itself: when gits prints to a terminal, git is told to use them.
 */
pub fn git(cwd: &Path, args: &[&str], quiet: bool) -> Result<(), String> {
    let mut all: Vec<&str> = Vec::new();
    if !quiet && colors() {
        all.extend_from_slice(&["-c", "color.ui=always"]);
    }
    all.extend_from_slice(args);

    let options = if quiet {
        Options::new().pwd(cwd).forward_stderr()
    } else {
        Options::new().pwd(cwd).forward()
    };
    let out =
        cli("git", &all, options).map_err(|e| format!("can't run git (is it installed?): {e}"))?;
    if out.success() {
        Ok(())
    } else {
        Err(format!(
            "git {} failed in >{}< ({})",
            args.join(" "),
            cwd.display(),
            out.status()
        ))
    }
}

// git with stdout captured (trimmed at the end), stderr dropped
pub fn git_out(cwd: &Path, args: &[&str]) -> Result<String, String> {
    let out = cli("git", args, Options::new().pwd(cwd))
        .map_err(|e| format!("can't run git (is it installed?): {e}"))?;
    if !out.success() {
        return Err(format!(
            "git {} failed in >{}<",
            args.join(" "),
            cwd.display()
        ));
    }
    Ok(out.stdout_text().trim_end().to_string())
}

pub fn is_url(source: &str) -> bool {
    source.starts_with("http://") || source.starts_with("https://")
}

// content of an url, through curl (fallback wget): no http / tls crate needed
pub fn download(url: &str) -> Result<Vec<u8>, String> {
    let attempts: [(&str, &[&str]); 2] = [("curl", &["-fsSL"]), ("wget", &["-q", "-O", "-"])];
    let mut last = String::from("neither curl nor wget found");
    for (program, args) in attempts {
        let mut all: Vec<&str> = args.to_vec();
        all.push(url);
        match cli(program, &all, Options::new()) {
            Ok(o) if o.success() && !o.stdout.is_empty() => return Ok(o.stdout),
            Ok(o) => {
                last = format!("{program} failed for >{url}<: {}", o.stderr_text().trim());
                // the program exists and answered, the other one would say the same
                break;
            }
            Err(_) => continue,
        }
    }
    Err(last)
}

// content of an url or of a local file ("~/" expanded)
pub fn fetch(source: &str) -> Result<Vec<u8>, String> {
    if is_url(source) {
        download(source)
    } else {
        let path = expand_tilde(source);
        fs::read(&path).map_err(|e| format!("can't read >{}<: {e}", path.display()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_normalizes() {
        assert_eq!(
            absolute(Path::new("../.env"), Path::new("/a/b/.git")),
            PathBuf::from("/a/b/.env")
        );
        assert_eq!(
            absolute(Path::new("/x/./y/../z"), Path::new("/a")),
            PathBuf::from("/x/z")
        );
    }

    #[test]
    fn relative_paths() {
        assert_eq!(
            relative(Path::new("/a/b/.env"), Path::new("/a/b/.git")),
            PathBuf::from("../.env")
        );
        assert_eq!(
            relative(Path::new("/a/b/.git/xx.ts"), Path::new("/a/b/.git")),
            PathBuf::from("xx.ts")
        );
        assert_eq!(
            relative(Path::new("/a/c/d.txt"), Path::new("/a/b/.git")),
            PathBuf::from("../../c/d.txt")
        );
    }

    #[test]
    fn random_hex_length() {
        assert_eq!(random_hex(2).len(), 4);
        assert!(random_hex(4).bytes().all(|b| b.is_ascii_hexdigit()));
    }
}
