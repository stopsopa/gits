use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::cli::{cli, Options};
use crate::config::{self, Project};
use crate::crypt;
use crate::events;
use crate::socket::Lazy;
use crate::util::{self, 
    copy_file, git, git_out, green, interrupted, random_hex, red, unique_sibling, yellow,
};
use crate::Ctx;

/**
 * Global gitignore of the user (core.excludesFile) must not decide what is stored: a listed
 * ".env" ignored globally would silently never reach the storage. .gitignore files of the
 * storage repository itself still apply.
 */
const NO_GLOBAL_IGNORE: [&str; 2] = ["-c", "core.excludesFile=/dev/null"];

// the commit of decrypted files exists only in the temporary clone, identity of the user is not needed for it
const LOCAL_COMMIT: [&str; 6] = [
    "-c",
    "user.name=gits",
    "-c",
    "user.email=gits@localhost",
    "-c",
    "commit.gpgsign=false",
];

pub(crate) fn sgit(cwd: &Path, args: &[&str], quiet: bool) -> Result<(), String> {
    let mut all: Vec<&str> = NO_GLOBAL_IGNORE.to_vec();
    all.extend_from_slice(args);
    git(cwd, &all, quiet)
}

fn sgit_out(cwd: &Path, args: &[&str]) -> Result<String, String> {
    let mut all: Vec<&str> = NO_GLOBAL_IGNORE.to_vec();
    all.extend_from_slice(args);
    git_out(cwd, &all)
}

pub const ENV_PULL_TO_SYNC: &str = "GITS_PULL_TO_SYNC";

/**
 * GITS_PULL_TO_SYNC: a directory which holds the clone of the storage between the runs of gits,
 * instead of a fresh clone into a directory with a random name every time. Absolute or ~/...
 * (a relative path would be another directory for every project).
 */
// true once the directory of GITS_PULL_TO_SYNC is known to hold the clone of the storage:
// before that nothing in it is reset or removed (it can be a directory with something else)
static SYNC_VERIFIED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn sync_dir() -> Result<Option<PathBuf>, String> {
    let Some(value) = util::env(ENV_PULL_TO_SYNC) else {
        return Ok(None);
    };
    let path = util::expand_tilde(&value);
    if !path.is_absolute() {
        return Err(format!(
            "{ENV_PULL_TO_SYNC}=>{value}< has to be an absolute path or start with ~/"
        ));
    }
    Ok(Some(path))
}

/**
 * The kept clone back to what origin has (as far as this clone knows) and nothing else in it:
 * no local commit (the decrypted view, a commit which was not pushed), no staged or untracked file.
 */
fn restore(dir: &Path) {
    if !dir.join(".git").exists() {
        return;
    }
    let upstream = git_out(dir, &["rev-parse", "-q", "--verify", "@{upstream}"])
        .ok()
        .filter(|s| !s.is_empty());
    match upstream {
        Some(commit) => {
            let _ = sgit(dir, &["reset", "-q", "--hard", &commit], true);
        }
        None => {
            // the storage has no commits: back to a branch without commits
            let _ = git_out(dir, &["update-ref", "-d", "HEAD"]);
            let _ = git_out(dir, &["rm", "-r", "-q", "--cached", "--ignore-unmatch", "."]);
        }
    }
    let _ = sgit(dir, &["clean", "-q", "-f", "-d", "-x"], true);
}

/**
 * The directory of the clone of the storage.
 *
 * Normally: a directory with a random name (4 hex characters) in `base`, removed when the value
 * is dropped: however the command ends, nothing is left behind.
 *
 * With GITS_PULL_TO_SYNC: that directory, kept. When the value is dropped the clone is only
 * cleaned (see restore): decrypted files and local commits don't stay in the working tree.
 */
pub struct Temp {
    pub path: PathBuf,
    quiet: bool,
    keep: bool,
}

impl Temp {
    pub fn create(base: &Path, quiet: bool) -> Result<Temp, String> {
        if let Some(path) = sync_dir()? {
            fs::create_dir_all(&path).map_err(|e| {
                format!(
                    "can't create directory {ENV_PULL_TO_SYNC}=>{}<: {e}",
                    path.display()
                )
            })?;
            let path = fs::canonicalize(&path).unwrap_or(path);
            if !quiet {
                println!("_TARGETGITDIR: {} ({ENV_PULL_TO_SYNC})", path.display());
            }
            events::set("GITS_EVENT_TEMP_DIR", path.display().to_string());
            return Ok(Temp {
                path,
                quiet,
                keep: true,
            });
        }
        loop {
            let path = base.join(random_hex(2));
            if fs::symlink_metadata(&path).is_ok() {
                continue;
            }
            fs::create_dir(&path).map_err(|e| {
                format!("can't create temporary directory >{}<: {e}", path.display())
            })?;
            if !quiet {
                println!("_TARGETGITDIR: {}", path.display());
            }
            events::set("GITS_EVENT_TEMP_DIR", path.display().to_string());
            return Ok(Temp {
                path,
                quiet,
                keep: false,
            });
        }
    }
}

impl Drop for Temp {
    fn drop(&mut self) {
        if !self.quiet {
            let what = if self.keep {
                format!(
                    "\ngits keeping {} ({ENV_PULL_TO_SYNC})",
                    self.path.display()
                )
            } else {
                format!("\ngits cleaning {}", self.path.display())
            };
            println!("{}", yellow(&what));
        }
        // nothing can be stopped here any more: a failing script is only reported
        let args = [self.path.display().to_string()];
        events::fire_quietly("BEFORE_CLEANUP", &args, &[]);
        if self.keep {
            if SYNC_VERIFIED.load(std::sync::atomic::Ordering::SeqCst) {
                restore(&self.path);
            }
        } else {
            let _ = fs::remove_dir_all(&self.path);
        }
        events::fire_quietly("AFTER_CLEANUP", &args, &[]);
    }
}

// clone of the storage repository
pub struct Storage {
    pub root: PathBuf,
    pub branch: String,
    // commit which was cloned, None when the storage has no commits yet
    base: Option<String>,
}

impl Storage {
    pub fn clone(source: &str, dest: &Path, quiet: bool) -> Result<Storage, String> {
        // a local path (tests, mirrors) may be relative to the directory gits was started in
        let source = match fs::canonicalize(source) {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(_) => source.to_string(),
        };
        let event_args = [dest.display().to_string()];
        events::fire("BEFORE_CLONE", &event_args, &[])?;

        // GITS_PULL_TO_SYNC and the directory already has the clone: only what is new is fetched
        let reuse = dest.join(".git").exists();
        if reuse {
            let origin = git_out(dest, &["remote", "get-url", "origin"]).unwrap_or_default();
            let same = origin == source
                || fs::canonicalize(&origin)
                    .map(|p| p.to_string_lossy() == source)
                    .unwrap_or(false);
            if !same {
                return Err(format!(
                    "{ENV_PULL_TO_SYNC}=>{}< is a clone of >{origin}<, not of the storage GITS_SOURCE=>{source}<: \
                     remove that directory or point the variable somewhere else",
                    dest.display()
                ));
            }
        } else if fs::read_dir(dest).map(|mut d| d.next().is_some()).unwrap_or(false) {
            return Err(format!(
                "{ENV_PULL_TO_SYNC}=>{}< is not empty and not a clone of the storage: gits doesn't touch it, \
                 remove that directory or point the variable somewhere else",
                dest.display()
            ));
        }

        if sync_dir()?.is_some() {
            SYNC_VERIFIED.store(true, std::sync::atomic::Ordering::SeqCst);
        }

        let mut args = if reuse {
            vec!["fetch", "--prune", "origin"]
        } else {
            vec!["clone"]
        };
        if quiet {
            args.push("-q");
        }
        if !reuse {
            args.push(&source);
            args.push(".");
        }
        let cloned = if quiet {
            // isinsync: also the chatter of git on stderr is unwanted, it is shown only when the clone fails
            match cli("git", &args, Options::new().pwd(dest)) {
                Ok(out) if out.success() => Ok(()),
                Ok(out) => Err(out.stderr_text().trim().to_string()),
                Err(e) => Err(format!("can't run git (is it installed?): {e}")),
            }
        } else {
            git(dest, &args, false)
        };
        cloned.map_err(|e| {
            format!(
                "can't {} storage GITS_SOURCE=>{source}<: {e}",
                if reuse { "fetch" } else { "clone" }
            )
        })?;
        if reuse {
            // the branch stays the one the clone started with (the default branch of the storage);
            // whatever an interrupted run left is thrown away, then the branch is what was fetched
            restore(dest);
        }

        let branch = git_out(dest, &["symbolic-ref", "--short", "HEAD"])
            .unwrap_or_else(|_| "master".to_string());
        let base = git_out(dest, &["rev-parse", "--verify", "-q", "HEAD"])
            .ok()
            .filter(|s| !s.is_empty());

        events::set("GITS_EVENT_STORAGE_BRANCH", branch.clone());
        events::fire("AFTER_CLONE", &event_args, &[])?;

        Ok(Storage {
            root: dest.to_path_buf(),
            branch,
            base,
        })
    }

    // back to exactly what was cloned: "gits state" uses one clone for all projects
    pub fn reset(&self) -> Result<(), String> {
        if let Some(base) = &self.base {
            sgit(&self.root, &["reset", "-q", "--hard", base], true)?;
        } else {
            // nothing committed in the storage, but the previous project could have staged files
            let _ = sgit(
                &self.root,
                &["rm", "-r", "-q", "--cached", "--ignore-unmatch", "."],
                true,
            );
        }
        sgit(&self.root, &["clean", "-q", "-f", "-d", "-x"], true)
    }

    pub(crate) fn status(&self) -> Result<String, String> {
        sgit_out(&self.root, &["status", "-s"])
    }
}

pub enum Outcome {
    InSync,
    Differs,
    // at least one SOURCE doesn't exist
    Missing,
}

// what the lifecycle scripts know about the project from now on
fn project_context(dir: &Path, project: &Project) {
    events::set("GITS_EVENT_PROJECT_DIR", dir.display().to_string());
    events::set(
        "GITS_EVENT_CONFIG",
        config::config_path(dir).display().to_string(),
    );
    events::set("GITS_TARGETDIR", project.target_dir.clone());
    events::set("GITS_EVENT_LIST_COUNT", project.list.len().to_string());
    let list: Vec<String> = project
        .list
        .iter()
        .map(|e| {
            format!(
                "{}\t{}\t{}",
                if e.encrypted { "e" } else { "p" },
                e.source.display(),
                e.target
            )
        })
        .collect();
    events::set("GITS_EVENT_LIST", list.join("\n"));
}

fn storage_context(storage: &Storage, project: &Project) {
    events::set(
        "GITS_EVENT_STORAGE_DIR",
        storage.root.join(&project.target_dir).display().to_string(),
    );
}

// one of the per-file events: BEFORE_/AFTER_ DECRYPT, COPY, ENCRYPT
fn file_event(
    event: &str,
    storage: &Storage,
    project: &Project,
    entry: &config::Entry,
    plain: Option<&Path>,
) -> Result<(), String> {
    let stored = storage.root.join(&entry.target);
    let index = project
        .list
        .iter()
        .position(|e| e == entry)
        .map(|i| i + 1)
        .unwrap_or(0);
    let mut vars = vec![
        ("GITS_EVENT_FILE_SOURCE", entry.source.display().to_string()),
        ("GITS_EVENT_FILE_SOURCE_RAW", entry.raw_source.clone()),
        ("GITS_EVENT_FILE_TARGET", entry.target.clone()),
        ("GITS_EVENT_FILE_STORED", stored.display().to_string()),
        (
            "GITS_EVENT_FILE_ENCRYPTED",
            if entry.encrypted { "1" } else { "0" }.to_string(),
        ),
        ("GITS_EVENT_FILE_INDEX", index.to_string()),
    ];
    if let Some(plain) = plain {
        vars.push(("GITS_EVENT_FILE_PLAIN", plain.display().to_string()));
    }
    events::fire(
        event,
        &[
            entry.source.display().to_string(),
            stored.display().to_string(),
        ],
        &vars,
    )
}

/**
 * Files which are stored encrypted are decrypted inside the clone and committed there (the commit
 * never leaves the temporary directory). After that the clone looks as if the storage held plain
 * files, and "git status" / "git diff" against local files work the usual way, in plain text.
 */
fn decrypted_view(
    storage: &Storage,
    project: &Project,
    enc: &mut Lazy,
    quiet: bool,
) -> Result<(), String> {
    let mut done: HashSet<&str> = HashSet::new();
    let mut changed = false;

    for entry in project.list.iter().filter(|e| e.encrypted) {
        if !done.insert(entry.target.as_str()) {
            continue;
        }
        let stored = storage.root.join(&entry.target);
        if !stored.is_file() {
            continue;
        }
        file_event("BEFORE_DECRYPT", storage, project, entry, None)?;
        let plain = unique_sibling(&stored);
        match enc.get()?.decode(&stored, &plain) {
            Ok(()) => {
                fs::rename(&plain, &stored)
                    .map_err(|e| format!("can't replace >{}<: {e}", stored.display()))?;
                changed = true;
            }
            Err(e) if e.malformed() => {
                let _ = fs::remove_file(&plain);
                if !quiet {
                    println!(
                        "{}",
                        yellow(&format!(
                            "'{}' is marked :e: but it is stored not encrypted, it will be encrypted by the next: gits push --yes",
                            entry.target
                        ))
                    );
                }
            }
            Err(e) => {
                let _ = fs::remove_file(&plain);
                return Err(format!("can't decrypt '{}': {e}", entry.target));
            }
        }
        file_event("AFTER_DECRYPT", storage, project, entry, None)?;
    }

    if changed {
        sgit(&storage.root, &["add", "-A"], true)?;
        let mut args: Vec<&str> = LOCAL_COMMIT.to_vec();
        args.extend_from_slice(&[
            "commit",
            "-q",
            "--no-verify",
            "-m",
            "gits: decrypted view, local only, never pushed",
        ]);
        sgit(&storage.root, &args, true)?;
    }
    Ok(())
}

// every SOURCE over its TARGET in the clone. true: at least one SOURCE is missing
fn copy_sources(storage: &Storage, project: &Project) -> Result<bool, String> {
    let mut missing = false;
    for entry in &project.list {
        if entry.source.is_file() {
            file_event("BEFORE_COPY", storage, project, entry, None)?;
            copy_file(&entry.source, &storage.root.join(&entry.target))?;
            file_event("AFTER_COPY", storage, project, entry, None)?;
        } else {
            missing = true;
            eprintln!(
                "{}",
                red(&format!(
                    "gits error: source file '{}' doesn't exist",
                    entry.source.display()
                ))
            );
        }
    }
    Ok(missing)
}

// the common part of diff, isinsync, state and of push / pull without --yes
pub fn check(
    storage: &Storage,
    project: &Project,
    enc: &mut Lazy,
    quiet: bool,
) -> Result<Outcome, String> {
    storage_context(storage, project);
    decrypted_view(storage, project, enc, quiet)?;
    let missing = copy_sources(storage, project)?;

    events::fire("BEFORE_COMPARE", &[], &[])?;
    let outcome = if missing {
        Outcome::Missing
    } else if storage.status()?.trim().is_empty() {
        Outcome::InSync
    } else {
        Outcome::Differs
    };
    let result = match outcome {
        Outcome::InSync => "insync",
        Outcome::Differs => "differs",
        Outcome::Missing => "missing",
    };
    let changed: Vec<String> = match outcome {
        Outcome::InSync => Vec::new(),
        _ => changed_sources(storage, project)
            .iter()
            .map(|entry| entry.source.display().to_string())
            .collect(),
    };
    events::fire(
        "AFTER_COMPARE",
        &[result.to_string()],
        &[
            ("GITS_EVENT_RESULT", result.to_string()),
            ("GITS_EVENT_CHANGED", changed.join("\n")),
        ],
    )?;
    Ok(outcome)
}

/**
 * "git@github.com:owner/repo.git" (also https://, ssh://, git://) -> ("https://github.com/owner/repo", host).
 * None: not something with a web page (local directory).
 */
pub fn web_base(source: &str) -> Option<(String, String)> {
    let source = source.trim();
    let (host, path) = if let Some((_, rest)) = source.split_once("://") {
        let (authority, path) = rest.split_once('/')?;
        let host = authority
            .rsplit_once('@')
            .map(|(_, h)| h)
            .unwrap_or(authority);
        let host = host.split_once(':').map(|(h, _)| h).unwrap_or(host);
        (host, path)
    } else {
        let (authority, path) = source.split_once(':')?;
        if !authority.contains('@') || authority.contains('/') {
            return None;
        }
        (authority.rsplit_once('@')?.1, path)
    };
    let path = path.trim_matches('/');
    let path = path.strip_suffix(".git").unwrap_or(path);
    if host.is_empty() || path.is_empty() {
        return None;
    }
    Some((format!("https://{host}/{path}"), host.to_string()))
}

pub fn url_for(source: &str, branch: &str, target_dir: &str) -> String {
    match web_base(source) {
        Some((base, host)) if host.contains("github") => {
            format!("{base}/tree/{branch}/{target_dir}")
        }
        Some((base, _)) => format!("{base}/raw/{branch}/{target_dir}"),
        None => format!("{} (directory {target_dir})", source.trim_end_matches('/')),
    }
}

// default branch of the storage without cloning it, "master" when it can't be found out
pub fn remote_branch(source: &str, cwd: &Path) -> String {
    let source = match fs::canonicalize(source) {
        Ok(p) => p.to_string_lossy().to_string(),
        Err(_) => source.to_string(),
    };
    git_out(cwd, &["ls-remote", "--symref", &source, "HEAD"])
        .ok()
        .and_then(|out| {
            out.lines().find_map(|l| {
                l.strip_prefix("ref: refs/heads/")
                    .and_then(|r| r.split_whitespace().next())
                    .map(|b| b.to_string())
            })
        })
        .unwrap_or_else(|| "master".to_string())
}

fn final_url(ctx: &Ctx, storage: &Storage, project: &Project) {
    println!(
        "final url {}",
        url_for(&ctx.source, &storage.branch, &project.target_dir)
    );
}

pub(crate) fn load(ctx: &Ctx, quiet: bool) -> Result<Project, String> {
    let loaded = config::load(&ctx.cwd, quiet)?;
    if !quiet {
        print!("{}", loaded.output);
    }
    loaded_event(&ctx.cwd, &loaded)?;
    Ok(loaded.project)
}

// the config was executed: its scripts join the ones of the environment, and CONFIG_LOADED fires
fn loaded_event(dir: &Path, loaded: &config::Loaded) -> Result<(), String> {
    project_context(dir, &loaded.project);
    events::set_config_scripts(loaded.scripts.clone());
    events::fire("CONFIG_LOADED", &[], &[])
}

/**
 * Without GITS_ENCRYPTION_SOCKET ":e:" is ignored: the files are transported as they are, like "::".
 * With one exception: a file which is already stored encrypted. Copied as it is it would overwrite
 * the local file with encrypted text (pull) or replace the encrypted file by a plain one (push),
 * so that is an error: once something is encrypted, going back is an explicit "gits crypt decrypt".
 *
 * Returns the project as the rest of the command should see it.
 */
pub(crate) fn without_socket(
    ctx: &Ctx,
    storage: &Storage,
    mut project: Project,
    quiet: bool,
) -> Result<Project, String> {
    if ctx.socket.is_some() || !project.list.iter().any(|e| e.encrypted) {
        return Ok(project);
    }
    for entry in project.list.iter().filter(|e| e.encrypted) {
        if crypt::slots(&storage.root.join(&entry.target)).is_some() {
            return Err(format!(
                "'{}' is stored encrypted but env var {} is not defined, \
                 it has to point to the unix socket of the encoder process \
                 (to store everything not encrypted again: gits crypt decrypt)",
                entry.target,
                crate::socket::ENV_SOCKET
            ));
        }
    }
    if !quiet {
        println!(
            "{}",
            yellow(&format!(
                "env var {} is not defined: ':e:' is ignored, files are transported as they are",
                crate::socket::ENV_SOCKET
            ))
        );
    }
    for entry in project.list.iter_mut() {
        entry.encrypted = false;
    }
    Ok(project)
}

// directory where "git diff" / "git status" are run: the one of the project when the storage has it
fn view_dir(storage: &Storage, project: &Project) -> PathBuf {
    let dir = storage.root.join(&project.target_dir);
    if dir.is_dir() {
        dir
    } else {
        storage.root.clone()
    }
}

pub fn url(ctx: &Ctx) -> Result<i32, String> {
    let project = load(ctx, false)?;
    let branch = remote_branch(&ctx.source, &ctx.cwd);
    println!(
        "final url {}",
        url_for(&ctx.source, &branch, &project.target_dir)
    );
    Ok(0)
}

pub fn diff(ctx: &Ctx) -> Result<i32, String> {
    let project = load(ctx, false)?;
    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;
    let project = without_socket(ctx, &storage, project, false)?;
    let mut enc = Lazy::new(ctx.socket.clone());

    let code = match check(&storage, &project, &mut enc, false)? {
        Outcome::InSync => {
            println!("{}", green("\n    files are in sync\n"));
            0
        }
        Outcome::Missing => {
            println!(
                "{}",
                red("\n    files are not in sync - at least one source file is missing\n")
            );
            1
        }
        Outcome::Differs => {
            println!("{}", red("\n    files are not in sync\n"));
            // files which are new for the storage are untracked, "git diff" would not show them
            let _ = sgit(&storage.root, &["add", "-A", "-N"], true);
            let dir = view_dir(&storage, &project);
            let _ = sgit(&dir, &["diff"], false);
            let _ = sgit(&dir, &["status"], false);
            changed_files(&storage, &project);
            1
        }
    };
    final_url(ctx, &storage, &project);
    Ok(code)
}

/**
 * Paths inside the storage which differ from what is stored: modified, new, deleted.
 * "git status --porcelain -z": entries "XY <path>" separated by NUL, paths as they are (no quoting).
 * A rename has a second entry with the old path and no "XY " in front of it, it is skipped.
 */
fn changed_targets(status: &str) -> HashSet<String> {
    let mut out = HashSet::new();
    let mut parts = status.split('\0');
    while let Some(part) = parts.next() {
        if part.len() < 4 {
            continue;
        }
        let (code, path) = part.split_at(3);
        out.insert(path.to_string());
        if code.starts_with('R') || code.starts_with('C') {
            parts.next();
        }
    }
    out
}

/**
 * Local files (SOURCE, absolute paths) which differ from what is stored, one per line:
 * in a terminal of an editor a path can be clicked to open the file.
 * Printed after "git status", just above the final url.
 */
fn changed_sources<'a>(storage: &Storage, project: &'a Project) -> Vec<&'a config::Entry> {
    let status = match sgit_out(
        &storage.root,
        &["status", "--porcelain", "-z", "--untracked-files=all"],
    ) {
        Ok(status) => status,
        Err(_) => return Vec::new(),
    };
    let changed = changed_targets(&status);
    project
        .list
        .iter()
        .filter(|entry| changed.contains(&entry.target))
        .collect()
}

fn changed_files(storage: &Storage, project: &Project) {
    let files = changed_sources(storage, project);
    if files.is_empty() {
        return;
    }
    println!("\nchanged files:");
    for entry in files {
        println!("  {}", util::blue(&entry.source.display().to_string()));
    }
    println!();
}

// only the exit code: 0 in sync, 1 not in sync (errors are reported by the caller with 2)
pub fn isinsync(ctx: &Ctx) -> Result<i32, String> {
    let project = load(ctx, true)?;
    let temp = Temp::create(&ctx.cwd, true)?;
    let storage = Storage::clone(&ctx.source, &temp.path, true)?;
    let project = without_socket(ctx, &storage, project, true)?;
    let mut enc = Lazy::new(ctx.socket.clone());
    Ok(match check(&storage, &project, &mut enc, true)? {
        Outcome::InSync => 0,
        _ => 1,
    })
}

// push / pull without --yes: nothing is changed, only the answer whether there is anything to do
fn dry(ctx: &Ctx, action: &str) -> Result<i32, String> {
    let project = load(ctx, false)?;
    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;
    let project = without_socket(ctx, &storage, project, false)?;
    let mut enc = Lazy::new(ctx.socket.clone());

    let code = match check(&storage, &project, &mut enc, false)? {
        Outcome::InSync => {
            println!("{}", green("\n    files are in sync\n"));
            0
        }
        other => {
            if matches!(other, Outcome::Differs) {
                println!("{}", red("\n    files are not in sync\n"));
                let _ = sgit(&storage.root, &["add", "-A", "-N"], true);
                let _ = sgit(&view_dir(&storage, &project), &["status"], false);
            } else {
                println!(
                    "{}",
                    red("\n    files are not in sync - at least one source file is missing\n")
                );
            }
            println!(
                "{}",
                red(&format!(
                    "gits error: files are not in sync, nothing was changed. If you are sure that you want to {action} them: gits {action} --yes"
                ))
            );
            1
        }
    };
    final_url(ctx, &storage, &project);
    Ok(code)
}

pub fn push(ctx: &Ctx, yes: bool) -> Result<i32, String> {
    if !yes {
        return dry(ctx, "push");
    }

    let project = load(ctx, false)?;

    for entry in &project.list {
        let in_directory = Path::new(&entry.target)
            .parent()
            .map(|p| !p.as_os_str().is_empty())
            .unwrap_or(false);
        if !in_directory {
            return Err(format!(
                "target file '{0}' should be in a directory, like 'xxx/{0}'",
                entry.target
            ));
        }
    }

    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;
    let project = without_socket(ctx, &storage, project, false)?;
    storage_context(&storage, &project);
    let mut enc = Lazy::new(ctx.socket.clone());
    let mut missing = false;

    for entry in &project.list {
        if !entry.source.is_file() {
            missing = true;
            eprintln!(
                "{}",
                red(&format!(
                    "gits error: source file '{}' doesn't exist",
                    entry.source.display()
                ))
            );
            continue;
        }
        let stored = storage.root.join(&entry.target);

        if !entry.encrypted {
            println!(
                "{}",
                yellow(&format!("'{}' -> '{}'", entry.raw_source, entry.target))
            );
            file_event("BEFORE_COPY", &storage, &project, entry, None)?;
            copy_file(&entry.source, &stored)?;
            file_event("AFTER_COPY", &storage, &project, entry, None)?;
            continue;
        }

        println!(
            "{}",
            yellow(&format!(
                "'{}' -> '{}' (encrypted)",
                entry.raw_source, entry.target
            ))
        );

        // What is stored is compared in plain text: when nothing was edited the stored file is
        // left byte for byte as it is, whatever the encoder would produce for the same content.
        let mut unchanged = false;
        if stored.is_file() {
            file_event("BEFORE_DECRYPT", &storage, &project, entry, None)?;
            let plain = unique_sibling(&stored);
            let decoded = enc.get()?.decode(&stored, &plain);
            match decoded {
                Ok(()) => {
                    unchanged = match (fs::read(&plain), fs::read(&entry.source)) {
                        (Ok(a), Ok(b)) => a == b,
                        _ => false,
                    };
                    let _ = fs::remove_file(&plain);
                }
                // stored plain until now: it is replaced by the encrypted one
                Err(e) if e.malformed() => {
                    let _ = fs::remove_file(&plain);
                }
                Err(e) => {
                    let _ = fs::remove_file(&plain);
                    return Err(format!("can't decrypt '{}': {e}", entry.target));
                }
            }
            file_event("AFTER_DECRYPT", &storage, &project, entry, None)?;
        }

        if !unchanged {
            // plain copy next to the target, under a name which doesn't exist, only for the moment of encryption.
            // The existing target is the "previous version" for the encoder: lines which were not edited stay as they are.
            let raw = unique_sibling(&stored);
            copy_file(&entry.source, &raw)?;
            // a script which stops the push here must not leave the plain copy behind
            if let Err(e) = file_event("BEFORE_ENCRYPT", &storage, &project, entry, Some(&raw)) {
                let _ = fs::remove_file(&raw);
                return Err(e);
            }
            let encoded = enc
                .get()
                .and_then(|e| e.encode(&raw, &stored).map_err(|e| e.to_string()));
            let _ = fs::remove_file(&raw);
            encoded.map_err(|e| format!("can't encrypt '{}': {e}", entry.raw_source))?;
            file_event("AFTER_ENCRYPT", &storage, &project, entry, None)?;
        }
    }

    if storage.status()?.trim().is_empty() {
        println!("{}", green("\n    files are in sync\n"));
        final_url(ctx, &storage, &project);
        return Ok(if missing { 1 } else { 0 });
    }

    events::fire("BEFORE_COMMIT", &[], &[])?;
    sgit(&storage.root, &["add", "-A"], false)?;
    let message = format!("gits push {}", project.target_dir);
    sgit(&storage.root, &["commit", "-q", "-m", &message], false)?;
    let commit = git_out(&storage.root, &["rev-parse", "HEAD"]).unwrap_or_default();
    let commit_args = [commit.clone()];
    let commit_vars = [("GITS_EVENT_COMMIT", commit)];
    events::fire("AFTER_COMMIT", &commit_args, &commit_vars)?;

    events::fire("BEFORE_PUSH", &commit_args, &commit_vars)?;
    sgit(&storage.root, &["push", "origin", "HEAD"], false)?;
    events::fire("AFTER_PUSH", &commit_args, &commit_vars)?;

    println!("{}", green("\n    files pushed\n"));
    final_url(ctx, &storage, &project);

    if missing {
        eprintln!(
            "{}",
            red("gits error: the files above which don't exist were not pushed, the rest was")
        );
        return Ok(1);
    }
    Ok(0)
}

/**
 * One element of pull: TARGET in the clone -> SOURCE on this machine.
 * Ok(false): the storage has no such file, nothing was done (said on stderr).
 * Err: the file could not be decrypted or written, the local file is as it was.
 */
fn pull_entry(
    storage: &Storage,
    project: &Project,
    entry: &config::Entry,
    enc: &mut Lazy,
) -> Result<bool, String> {
    let stored = storage.root.join(&entry.target);
    if !stored.is_file() {
        eprintln!(
            "{}",
            red(&format!(
                "file '{}' doesn't exist in the storage, it might be worth to remove it from {}/{}",
                entry.target,
                config::GIT_DIR,
                config::CONFIG
            ))
        );
        return Ok(false);
    }

    println!(
        "{}",
        yellow(&format!("'{}' -> '{}'", entry.target, entry.raw_source))
    );

    if !entry.encrypted {
        file_event("BEFORE_COPY", storage, project, entry, None)?;
        copy_file(&stored, &entry.source)?;
        file_event("AFTER_COPY", storage, project, entry, None)?;
        return Ok(true);
    }

    // decrypted next to the stored file first: a failed decryption never touches the local file
    file_event("BEFORE_DECRYPT", storage, project, entry, None)?;
    let plain = unique_sibling(&stored);
    let decoded = enc.get()?.decode(&stored, &plain);
    if decoded.is_ok() || decoded.as_ref().is_err_and(|e| e.malformed()) {
        if let Err(e) = file_event("AFTER_DECRYPT", storage, project, entry, Some(&plain)) {
            let _ = fs::remove_file(&plain);
            return Err(e);
        }
        if let Err(e) = file_event("BEFORE_COPY", storage, project, entry, Some(&plain)) {
            let _ = fs::remove_file(&plain);
            return Err(e);
        }
    }
    let result = match decoded {
        Ok(()) => copy_file(&plain, &entry.source),
        Err(e) if e.malformed() => {
            println!(
                "{}",
                yellow(&format!(
                    "'{}' is marked :e: but it is stored not encrypted, copied as it is",
                    entry.target
                ))
            );
            copy_file(&stored, &entry.source)
        }
        Err(e) => Err(format!("can't decrypt '{}': {e}", entry.target)),
    };
    let _ = fs::remove_file(&plain);
    result?;
    file_event("AFTER_COPY", storage, project, entry, None)?;
    Ok(true)
}

pub fn pull(ctx: &Ctx, yes: bool) -> Result<i32, String> {
    if !yes {
        return dry(ctx, "pull");
    }

    let project = load(ctx, false)?;
    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;
    let mut project = without_socket(ctx, &storage, project, false)?;
    storage_context(&storage, &project);
    let mut enc = Lazy::new(ctx.socket.clone());
    let mut failed = false;

    /*
     * The config is usually an element of its own list, and the list in the storage can be newer
     * than the local one (another machine added a file, or changed "::" to ":e:"). Pulling with
     * the old list would miss the new files and, worse, copy a file which is encrypted by now
     * over the local one as it is. So the config is pulled first, and when it changed the list
     * is read again before anything else is touched.
     */
    let config_file = config::config_path(&ctx.cwd);
    let own = project
        .list
        .iter()
        .position(|entry| entry.source == config_file);
    if let Some(at) = own {
        let before = fs::read(&config_file).ok();
        pull_entry(&storage, &project, &project.list[at], &mut enc)?;
        if fs::read(&config_file).ok() != before {
            println!(
                "{}",
                yellow(&format!(
                    "{}/{} was different in the storage: it was pulled first and the list is read again",
                    config::GIT_DIR,
                    config::CONFIG
                ))
            );
            project = without_socket(ctx, &storage, load(ctx, false)?, true)?;
        }
    }

    for entry in &project.list {
        // already done above
        if own.is_some() && entry.source == config_file {
            continue;
        }
        if let Err(e) = pull_entry(&storage, &project, entry, &mut enc) {
            failed = true;
            eprintln!("{}", red(&format!("gits error: {e}")));
        }
    }

    if failed {
        println!(
            "{}",
            red("\n    files pulled, but not all of them (see above)\n")
        );
    } else {
        println!("{}", green("\n    files pulled\n"));
    }
    final_url(ctx, &storage, &project);
    Ok(if failed { 1 } else { 0 })
}

pub fn state(ctx: &Ctx) -> Result<i32, String> {
    let found = config::find(&ctx.cwd)?;

    if found.is_empty() {
        println!("\n  nothing found\n");
        return Ok(0);
    }

    // separates the report from whatever was in the terminal before
    let line = "=".repeat(116);
    println!("{}", green(&line));
    print!("{}", "\n".repeat(11));
    println!("{}", green(&line));

    let temp = Temp::create(&ctx.cwd, false)?;
    let mut storage: Option<Storage> = None;
    let mut enc = Lazy::new(ctx.socket.clone());

    let count = found.len();
    let mut success = 0;
    let mut errors = 0;

    for (i, project) in found.iter().enumerate() {
        // Ctrl+C: the summary and the cleanup still happen, the rest of the projects doesn't
        if interrupted() {
            break;
        }
        let config = project.config_display();
        println!("{} {} : {count} >{config}<", ">".repeat(51), i + 1);

        let dir = ctx.cwd.join(&project.dir);
        let dir = fs::canonicalize(&dir).unwrap_or(dir);
        println!("\n  cd \"{}\"\n  gits diff\n", dir.display());

        // what the scripts know about the previous project is gone, its own scripts too
        events::set_config_scripts(Default::default());
        for name in [
            "GITS_EVENT_CONFIG",
            "GITS_TARGETDIR",
            "GITS_EVENT_LIST_COUNT",
            "GITS_EVENT_LIST",
            "GITS_EVENT_STORAGE_DIR",
        ] {
            events::unset(name);
        }
        events::set("GITS_EVENT_PROJECT_DIR", dir.display().to_string());
        let index_vars = [
            ("GITS_EVENT_STATE_INDEX", (i + 1).to_string()),
            ("GITS_EVENT_STATE_COUNT", count.to_string()),
        ];
        events::fire(
            "BEFORE_PROJECT",
            &[
                dir.display().to_string(),
                (i + 1).to_string(),
                count.to_string(),
            ],
            &index_vars,
        )?;
        // however the check of this project ends
        let after = |result: &str, success: usize, errors: usize| {
            events::fire(
                "AFTER_PROJECT",
                &[dir.display().to_string(), result.to_string()],
                &[
                    index_vars[0].clone(),
                    index_vars[1].clone(),
                    ("GITS_EVENT_RESULT", result.to_string()),
                    ("GITS_EVENT_COUNT_SUCCESS", success.to_string()),
                    ("GITS_EVENT_COUNT_ERROR", errors.to_string()),
                ],
            )
        };

        let loaded = match config::load(&dir, false).and_then(|l| {
            print!("{}", l.output);
            loaded_event(&dir, &l).map(|_| l)
        }) {
            Ok(l) => l,
            Err(e) => {
                println!("{}", red(&format!("gits error: {e}")));
                errors += 1;
                after("error", success, errors)?;
                continue;
            }
        };

        // one clone for all projects, made when the first of them needs it
        match &storage {
            None => {
                println!(
                    "{}",
                    green(&format!(
                        "cloning directory '{}' for '{config}'",
                        temp.path.display()
                    ))
                );
                storage = Some(Storage::clone(&ctx.source, &temp.path, false)?);
                println!("cloned..");
            }
            Some(s) => {
                println!(
                    "{}",
                    green(&format!(
                        "directory '{}' for '{config}' already exist",
                        temp.path.display()
                    ))
                );
                s.reset()?;
            }
        }
        let storage = storage.as_ref().unwrap();

        let result = match without_socket(ctx, storage, loaded.project, false)
            .and_then(|project| check(storage, &project, &mut enc, false))
        {
            Ok(Outcome::InSync) => {
                println!("{}", green("    files are in sync"));
                success += 1;
                "insync"
            }
            Ok(Outcome::Missing) => {
                println!(
                    "{}",
                    red("    files are not in sync - at least one source file is missing")
                );
                errors += 1;
                "missing"
            }
            Ok(Outcome::Differs) => {
                println!("{}", red("    files are not in sync"));
                let _ = sgit(&storage.root, &["add", "-A", "-N"], true);
                let _ = sgit(&storage.root, &["status"], false);
                errors += 1;
                "differs"
            }
            Err(e) => {
                println!("{}", red(&format!("gits error: {e}")));
                errors += 1;
                "error"
            }
        };
        after(result, success, errors)?;
    }

    println!();
    println!("{}", green(&format!("COUNT_SUCCESS : {success}")));
    println!("{}", red(&format!("COUNT_ERROR   : {errors}")));
    println!();

    Ok(if errors > 0 { 1 } else { 0 })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn changed_targets_of_status() {
        let status =
            " M d/test.txt\0 A d/sub dir/new \"file\".txt\0R  d/new.txt\0d/old.txt\0?? d/x\0";
        let got = changed_targets(status);
        let mut list: Vec<&str> = got.iter().map(|s| s.as_str()).collect();
        list.sort();
        assert_eq!(
            list,
            vec![
                "d/new.txt",
                "d/sub dir/new \"file\".txt",
                "d/test.txt",
                "d/x"
            ]
        );
        assert!(changed_targets("").is_empty());
    }

    #[test]
    fn urls() {
        assert_eq!(
            url_for(
                "git@github.com:stopsopa/gitstorage.git",
                "master",
                "git@github.com:stopsopa__gitstorage.git"
            ),
            "https://github.com/stopsopa/gitstorage/tree/master/git@github.com:stopsopa__gitstorage.git"
        );
        // dots in the name of the repository stay
        assert_eq!(
            url_for(
                "git@github.com:stopsopa/stopsopa.github.io.git",
                "main",
                "d"
            ),
            "https://github.com/stopsopa/stopsopa.github.io/tree/main/d"
        );
        assert_eq!(
            url_for("https://github.com/o/r.git", "main", "d"),
            "https://github.com/o/r/tree/main/d"
        );
        assert_eq!(
            url_for("ssh://git@github.example.net:2222/o/r.git", "main", "d"),
            "https://github.example.net/o/r/tree/main/d"
        );
        assert_eq!(
            url_for("git@gitlab.com:group/sub/r.git", "main", "d"),
            "https://gitlab.com/group/sub/r/raw/main/d"
        );
        assert_eq!(
            url_for("/tmp/storage/", "main", "d"),
            "/tmp/storage (directory d)"
        );
        assert_eq!(
            url_for("relative/storage", "main", "d"),
            "relative/storage (directory d)"
        );
    }
}
