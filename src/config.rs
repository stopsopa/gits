use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::cli::{cli, Options};
use crate::util::{absolute, expand_tilde, git_out, random_hex, yellow};

pub const GIT_DIR: &str = ".git";
pub const CONFIG: &str = "gits.sh";
// config of the original gitstorage.sh, migrated to CONFIG when met
pub const LEGACY: &str = "gitstorage-config.sh";

pub const ENV_SHELL: &str = "GITSTORAGETESHELL";
pub const DEFAULT_SHELL: &str = "/bin/bash";

pub const SEP_PLAIN: &str = "::";
pub const SEP_ENCRYPTED: &str = ":e:";

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    // SOURCE as written in the config, for messages
    pub raw_source: String,
    // SOURCE resolved to an absolute path on this machine
    pub source: PathBuf,
    // TARGET: path inside the storage repository
    pub target: String,
    // SOURCE:e:TARGET
    pub encrypted: bool,
}

#[derive(Debug)]
pub struct Project {
    // GITSTORAGETARGETDIR
    pub target_dir: String,
    pub list: Vec<Entry>,
}

pub fn config_path(dir: &Path) -> PathBuf {
    dir.join(GIT_DIR).join(CONFIG)
}

pub fn legacy_path(dir: &Path) -> PathBuf {
    dir.join(GIT_DIR).join(LEGACY)
}

/**
 * "SOURCE::TARGET" or "SOURCE:e:TARGET" -> (SOURCE, encrypted, TARGET).
 * The separator which comes first wins: TARGET normally contains colons itself
 * (git@github.com:owner__repo.git/...), SOURCE normally doesn't.
 */
pub fn split_entry(raw: &str) -> Result<(String, bool, String), String> {
    let plain = raw.find(SEP_PLAIN);
    let encrypted = raw.find(SEP_ENCRYPTED);
    let (at, len, is_encrypted) = match (plain, encrypted) {
        (Some(p), Some(e)) if e < p => (e, SEP_ENCRYPTED.len(), true),
        (Some(p), _) => (p, SEP_PLAIN.len(), false),
        (None, Some(e)) => (e, SEP_ENCRYPTED.len(), true),
        (None, None) => {
            return Err(format!(
                "element >{raw}< of GITSTORAGELIST is neither \"SOURCE::TARGET\" nor \"SOURCE:e:TARGET\""
            ))
        }
    };
    let source = raw[..at].to_string();
    let target = raw[at + len..].to_string();
    if source.is_empty() || target.is_empty() {
        return Err(format!(
            "element >{raw}< of GITSTORAGELIST has empty SOURCE or TARGET"
        ));
    }
    Ok((source, is_encrypted, target))
}

/**
 * SOURCE on this machine:
 *   /abs/path   as it is
 *   ~/path      in the home directory
 *   other       relative to the directory of the config (.git), so "../.env" is .env of the project
 */
pub fn resolve_source(raw: &str, project_dir: &Path) -> PathBuf {
    if raw.starts_with('/') {
        return absolute(Path::new(raw), project_dir);
    }
    if raw == "~" || raw.starts_with("~/") {
        return absolute(&expand_tilde(raw), project_dir);
    }
    absolute(Path::new(raw), &project_dir.join(GIT_DIR))
}

// TARGET is joined to the path of the clone, it must not be able to leave it
pub fn valid_target(target: &str) -> Result<(), String> {
    let path = Path::new(target);
    if path.is_absolute() {
        return Err(format!(
            "TARGET >{target}< has to be a relative path inside the storage repository"
        ));
    }
    for c in path.components() {
        match c {
            Component::Normal(_) => {}
            Component::CurDir => {}
            _ => return Err(format!("TARGET >{target}< must not contain '..'")),
        }
    }
    if target.starts_with(".git/") || target == ".git" {
        return Err(format!(
            "TARGET >{target}< must not point into .git of the storage repository"
        ));
    }
    Ok(())
}

pub fn shell() -> String {
    crate::util::env(ENV_SHELL).unwrap_or_else(|| DEFAULT_SHELL.to_string())
}

pub struct Loaded {
    pub project: Project,
    // whatever the config printed while it was executed
    pub output: String,
}

/**
 * The config is a shell script, so the only way to know what it defines is to execute it:
 * with the shell from GITSTORAGETESHELL, from the root of the project, and then to ask that shell
 * for GITSTORAGETARGETDIR and GITSTORAGELIST. Whatever the config prints is separated from that
 * answer with a marker line.
 *
 * When .git/gits.sh is missing and .git/gitstorage-config.sh is there, it is migrated first.
 */
pub fn load(dir: &Path, quiet: bool) -> Result<Loaded, String> {
    let dir = absolute(
        dir,
        &std::env::current_dir().map_err(|e| format!("can't read current directory: {e}"))?,
    );
    let config = config_path(&dir);

    if !config.is_file() {
        if legacy_path(&dir).is_file() {
            migrate(&dir, quiet)?;
        } else {
            return Err(format!(
                "config >{}< doesn't exist, create it with: gits init",
                config.display()
            ));
        }
    }

    let marker = format!("__gits_marker_{}_{}__", std::process::id(), random_hex(8));
    let script = r#". "./$1"
printf '\n%s\n' "$2"
printf '%s\0' "$GITSTORAGETARGETDIR" "${GITSTORAGELIST[@]}"
"#;
    let shell = shell();
    // what the config prints on stderr is shown at once, its stdout is needed here
    let config_file = format!("{GIT_DIR}/{CONFIG}");
    let out = cli(
        &shell,
        ["-c", script, "gits", &config_file, &marker],
        Options::new().pwd(&dir).forward_stderr(),
    )
    .map_err(|e| {
        format!(
            "can't run shell {ENV_SHELL}=>{shell}< to read >{}<: {e}",
            config.display()
        )
    })?;

    let needle = format!("\n{marker}\n");
    let at = rfind(&out.stdout, needle.as_bytes()).ok_or_else(|| {
        format!(
            "config >{}< executed with >{shell}< didn't run to its end ({}), does it call exit?",
            config.display(),
            out.status()
        )
    })?;

    let output = String::from_utf8_lossy(&out.stdout[..at]).to_string();
    let data = &out.stdout[at + needle.len()..];
    let mut parts = data
        .split(|b| *b == 0)
        .map(|p| String::from_utf8_lossy(p).to_string());

    let target_dir = parts.next().unwrap_or_default();
    if target_dir.trim().is_empty() {
        return Err(format!(
            "config >{}< doesn't define GITSTORAGETARGETDIR",
            config.display()
        ));
    }

    let mut list = Vec::new();
    for raw in parts {
        if raw.trim().is_empty() {
            continue;
        }
        let (raw_source, encrypted, target) =
            split_entry(&raw).map_err(|e| format!("config >{}<: {e}", config.display()))?;
        valid_target(&target).map_err(|e| format!("config >{}<: {e}", config.display()))?;
        list.push(Entry {
            source: resolve_source(&raw_source, &dir),
            raw_source,
            target,
            encrypted,
        });
    }

    if list.is_empty() {
        return Err(format!(
            "list GITSTORAGELIST in config >{}< shouldn't be empty",
            config.display()
        ));
    }

    Ok(Loaded {
        project: Project { target_dir, list },
        output,
    })
}

fn rfind(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    (0..=haystack.len() - needle.len())
        .rev()
        .find(|i| &haystack[*i..*i + needle.len()] == needle)
}

/**
 * Content of gitstorage-config.sh -> content of gits.sh.
 * Only the element which stores the config itself is changed:
 *   "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"  ->  "gits.sh::$GITSTORAGETARGETDIR/gits.sh"
 * (":e:" and ${GITSTORAGETARGETDIR} forms too). Everything else stays byte for byte.
 */
pub fn migrate_content(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim_start();
        let own = [SEP_PLAIN, SEP_ENCRYPTED].iter().find_map(|sep| {
            ['"', '\''].iter().find_map(|q| {
                let prefix = format!("{q}{LEGACY}{sep}");
                trimmed
                    .starts_with(&prefix)
                    .then_some((prefix, format!("{q}{CONFIG}{sep}"), *q))
            })
        });
        match own {
            Some((prefix, replacement, quote)) => {
                let mut changed = line.replacen(&prefix, &replacement, 1);
                let tail = format!("/{LEGACY}{quote}");
                if let Some(at) = changed.rfind(&tail) {
                    changed.replace_range(at..at + tail.len(), &format!("/{CONFIG}{quote}"));
                }
                out.push_str(&changed);
            }
            None => out.push_str(line),
        }
    }
    out
}

/**
 * .git/gitstorage-config.sh -> .git/gits.sh, the old file is removed.
 * Ok(false): nothing to migrate.
 */
pub fn migrate(dir: &Path, quiet: bool) -> Result<bool, String> {
    let legacy = legacy_path(dir);
    let config = config_path(dir);

    if !legacy.is_file() {
        return Ok(false);
    }
    if config.exists() {
        return Err(format!(
            "both >{}< and >{}< exist, the first one is used; compare them and remove the old one by hand",
            config.display(),
            legacy.display()
        ));
    }

    let text = fs::read_to_string(&legacy)
        .map_err(|e| format!("can't read >{}<: {e}", legacy.display()))?;
    fs::write(&config, migrate_content(&text))
        .map_err(|e| format!("can't write >{}<: {e}", config.display()))?;
    if let Ok(meta) = fs::metadata(&legacy) {
        let _ = fs::set_permissions(&config, meta.permissions());
    }
    fs::remove_file(&legacy).map_err(|e| {
        format!(
            ">{}< was created but the old >{}< can't be removed: {e}",
            config.display(),
            legacy.display()
        )
    })?;

    if !quiet {
        println!(
            "{}",
            yellow(&format!(
                "migrated {} -> {}",
                legacy.display(),
                config.display()
            ))
        );
    }
    Ok(true)
}

// "git@github.com:stopsopa/gits.git" -> "git@github.com:stopsopa__gits.git"
pub fn target_dir_from_remote(url: &str) -> String {
    url.trim().replace('/', "__")
}

pub fn remote_origin(dir: &Path) -> Result<String, String> {
    let url = git_out(dir, &["config", "--get", "remote.origin.url"]).unwrap_or_default();
    if url.trim().is_empty() {
        return Err(format!(
            "repository >{}< has no remote 'origin' (git config --get remote.origin.url), \
             the name of its directory in the storage is made from that url",
            dir.display()
        ));
    }
    Ok(url.trim().to_string())
}

#[derive(Debug, PartialEq)]
pub struct Found {
    // path relative to the directory which was searched: "." or "./a/b"
    pub dir: String,
    pub config: bool,
    pub legacy: bool,
}

impl Found {
    // path of the config which will be used, for messages
    pub fn config_display(&self) -> String {
        let file = if self.config { CONFIG } else { LEGACY };
        format!("{}/{GIT_DIR}/{file}", self.dir)
    }
}

/**
 * All projects below `base` (and `base` itself): directories with .git/gits.sh and/or
 * .git/gitstorage-config.sh. The equivalent of the original
 *
 *   find . -type d -name 'node_modules' -prune -o -type f -name "gitstorage-config.sh" -print | grep "/.git/gitstorage-config.sh"
 *
 * for both names: node_modules is not entered, symlinks to directories are not followed.
 * Directories named .git are not entered either (nothing useful can be nested there, and it is
 * most of the files on the disk). Sorted.
 */
pub fn find(base: &Path) -> Vec<Found> {
    let mut found = Vec::new();
    walk(base, ".", &mut found);
    found.sort_by(|a, b| a.dir.cmp(&b.dir));
    found
}

fn walk(dir: &Path, display: &str, found: &mut Vec<Found>) {
    let git = dir.join(GIT_DIR);
    let is_real_dir = fs::symlink_metadata(&git)
        .map(|m| m.is_dir())
        .unwrap_or(false);
    if is_real_dir {
        let config = git.join(CONFIG).is_file();
        let legacy = git.join(LEGACY).is_file();
        if config || legacy {
            found.push(Found {
                dir: display.to_string(),
                config,
                legacy,
            });
        }
    }

    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        // file type of the entry itself: a symlink to a directory is not a directory here
        let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
        if !is_dir {
            continue;
        }
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name == "node_modules" || name == GIT_DIR {
            continue;
        }
        walk(&entry.path(), &format!("{display}/{name}"), found);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_plain_and_encrypted() {
        assert_eq!(
            split_entry("gits.sh::git@github.com:o__r.git/gits.sh").unwrap(),
            (
                "gits.sh".to_string(),
                false,
                "git@github.com:o__r.git/gits.sh".to_string()
            )
        );
        assert_eq!(
            split_entry("../.env:e:git@github.com:o__r.git/.env").unwrap(),
            (
                "../.env".to_string(),
                true,
                "git@github.com:o__r.git/.env".to_string()
            )
        );
        // ":e:" later in TARGET doesn't make a plain element encrypted
        assert_eq!(
            split_entry("a::b:e:c").unwrap(),
            ("a".to_string(), false, "b:e:c".to_string())
        );
        assert_eq!(
            split_entry("~/Library/Application Support/x.json::d/x.json")
                .unwrap()
                .0,
            "~/Library/Application Support/x.json"
        );
        assert!(split_entry("no separator").is_err());
        assert!(split_entry("::target").is_err());
        assert!(split_entry("source::").is_err());
    }

    #[test]
    fn source_resolution() {
        let dir = Path::new("/w/project");
        assert_eq!(
            resolve_source("gits.sh", dir),
            PathBuf::from("/w/project/.git/gits.sh")
        );
        assert_eq!(
            resolve_source("../.env", dir),
            PathBuf::from("/w/project/.env")
        );
        assert_eq!(
            resolve_source("../../other/x", dir),
            PathBuf::from("/w/other/x")
        );
        assert_eq!(
            resolve_source("/etc/hosts", dir),
            PathBuf::from("/etc/hosts")
        );
    }

    #[test]
    fn targets() {
        assert!(valid_target("dir/file").is_ok());
        assert!(valid_target("git@github.com:o__r.git/a b/c").is_ok());
        assert!(valid_target("/abs/file").is_err());
        assert!(valid_target("dir/../../file").is_err());
        assert!(valid_target(".git/config").is_err());
    }

    #[test]
    fn target_dir() {
        assert_eq!(
            target_dir_from_remote("git@github.com:stopsopa/gitstorage.git\n"),
            "git@github.com:stopsopa__gitstorage.git"
        );
        assert_eq!(
            target_dir_from_remote("https://github.com/stopsopa/gits.git"),
            "https:____github.com__stopsopa__gits.git"
        );
    }

    #[test]
    fn migration_of_content() {
        let old = "GITSTORAGETARGETDIR=\"x\"\n# paths are solved from the directory where gitstorage-config.sh is\nGITSTORAGELIST=(\n    \"gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh\"\n    \"../other/.git/gitstorage-config.sh::$GITSTORAGETARGETDIR/other/gitstorage-config.sh\"\n)\n";
        let new = "GITSTORAGETARGETDIR=\"x\"\n# paths are solved from the directory where gitstorage-config.sh is\nGITSTORAGELIST=(\n    \"gits.sh::$GITSTORAGETARGETDIR/gits.sh\"\n    \"../other/.git/gitstorage-config.sh::$GITSTORAGETARGETDIR/other/gitstorage-config.sh\"\n)\n";
        assert_eq!(migrate_content(old), new);
        assert_eq!(
            migrate_content(
                "  \"gitstorage-config.sh:e:${GITSTORAGETARGETDIR}/gitstorage-config.sh\""
            ),
            "  \"gits.sh:e:${GITSTORAGETARGETDIR}/gits.sh\""
        );
        // already migrated content stays as it is
        assert_eq!(migrate_content(new), new);
    }
}
