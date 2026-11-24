use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::cli::{cli, Options};
use crate::config::{self, Project};
use crate::socket::Lazy;
use crate::util::{
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

fn sgit(cwd: &Path, args: &[&str], quiet: bool) -> Result<(), String> {
    let mut all: Vec<&str> = NO_GLOBAL_IGNORE.to_vec();
    all.extend_from_slice(args);
    git(cwd, &all, quiet)
}

fn sgit_out(cwd: &Path, args: &[&str]) -> Result<String, String> {
    let mut all: Vec<&str> = NO_GLOBAL_IGNORE.to_vec();
    all.extend_from_slice(args);
    git_out(cwd, &all)
}

/**
 * Directory with a random name (4 hex characters) in `base`, removed when the value is dropped:
 * however the command ends, nothing is left behind.
 */
pub struct Temp {
    pub path: PathBuf,
    quiet: bool,
}

impl Temp {
    pub fn create(base: &Path, quiet: bool) -> Result<Temp, String> {
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
            return Ok(Temp { path, quiet });
        }
    }
}

impl Drop for Temp {
    fn drop(&mut self) {
        if !self.quiet {
            println!(
                "{}",
                yellow(&format!("\ngits cleaning {}", self.path.display()))
            );
        }
        let _ = fs::remove_dir_all(&self.path);
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
        let mut args = vec!["clone"];
        if quiet {
            args.push("-q");
        }
        args.push(&source);
        args.push(".");
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
        cloned.map_err(|e| format!("can't clone storage GITSTORAGESOURCE=>{source}<: {e}"))?;

        let branch = git_out(dest, &["symbolic-ref", "--short", "HEAD"])
            .unwrap_or_else(|_| "master".to_string());
        let base = git_out(dest, &["rev-parse", "--verify", "-q", "HEAD"])
            .ok()
            .filter(|s| !s.is_empty());

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

    fn status(&self) -> Result<String, String> {
        sgit_out(&self.root, &["status", "-s"])
    }
}

pub enum Outcome {
    InSync,
    Differs,
    // at least one SOURCE doesn't exist
    Missing,
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
            copy_file(&entry.source, &storage.root.join(&entry.target))?;
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
    decrypted_view(storage, project, enc, quiet)?;
    if copy_sources(storage, project)? {
        return Ok(Outcome::Missing);
    }
    let status = storage.status()?;
    if status.trim().is_empty() {
        Ok(Outcome::InSync)
    } else {
        Ok(Outcome::Differs)
    }
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

fn load(ctx: &Ctx, quiet: bool) -> Result<Project, String> {
    let loaded = config::load(&ctx.cwd, quiet)?;
    if !quiet {
        print!("{}", loaded.output);
    }
    Ok(loaded.project)
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
            1
        }
    };
    final_url(ctx, &storage, &project);
    Ok(code)
}

// only the exit code: 0 in sync, 1 not in sync (errors are reported by the caller with 2)
pub fn isinsync(ctx: &Ctx) -> Result<i32, String> {
    let project = load(ctx, true)?;
    let temp = Temp::create(&ctx.cwd, true)?;
    let storage = Storage::clone(&ctx.source, &temp.path, true)?;
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
            copy_file(&entry.source, &stored)?;
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
        }

        if !unchanged {
            // plain copy next to the target, under a name which doesn't exist, only for the moment of encryption.
            // The existing target is the "previous version" for the encoder: lines which were not edited stay as they are.
            let raw = unique_sibling(&stored);
            copy_file(&entry.source, &raw)?;
            let encoded = enc
                .get()
                .and_then(|e| e.encode(&raw, &stored).map_err(|e| e.to_string()));
            let _ = fs::remove_file(&raw);
            encoded.map_err(|e| format!("can't encrypt '{}': {e}", entry.raw_source))?;
        }
    }

    if storage.status()?.trim().is_empty() {
        println!("{}", green("\n    files are in sync\n"));
        final_url(ctx, &storage, &project);
        return Ok(if missing { 1 } else { 0 });
    }

    sgit(&storage.root, &["add", "-A"], false)?;
    let message = format!("gits push {}", project.target_dir);
    sgit(&storage.root, &["commit", "-q", "-m", &message], false)?;
    sgit(&storage.root, &["push", "origin", "HEAD"], false)?;

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

pub fn pull(ctx: &Ctx, yes: bool) -> Result<i32, String> {
    if !yes {
        return dry(ctx, "pull");
    }

    let project = load(ctx, false)?;
    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;
    let mut enc = Lazy::new(ctx.socket.clone());
    let mut failed = false;

    for entry in &project.list {
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
            continue;
        }

        println!(
            "{}",
            yellow(&format!("'{}' -> '{}'", entry.target, entry.raw_source))
        );

        if !entry.encrypted {
            copy_file(&stored, &entry.source)?;
            continue;
        }

        // decrypted next to the stored file first: a failed decryption never touches the local file
        let plain = unique_sibling(&stored);
        let decoded = enc.get()?.decode(&stored, &plain);
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
        if let Err(e) = result {
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
    let found = config::find(&ctx.cwd);

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

        let loaded = match config::load(&dir, false) {
            Ok(l) => l,
            Err(e) => {
                println!("{}", red(&format!("gits error: {e}")));
                errors += 1;
                continue;
            }
        };
        print!("{}", loaded.output);

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

        match check(storage, &loaded.project, &mut enc, false) {
            Ok(Outcome::InSync) => {
                println!("{}", green("    files are in sync"));
                success += 1;
            }
            Ok(Outcome::Missing) => {
                println!(
                    "{}",
                    red("    files are not in sync - at least one source file is missing")
                );
                errors += 1;
            }
            Ok(Outcome::Differs) => {
                println!("{}", red("    files are not in sync"));
                let _ = sgit(&storage.root, &["add", "-A", "-N"], true);
                let _ = sgit(&storage.root, &["status"], false);
                errors += 1;
            }
            Err(e) => {
                println!("{}", red(&format!("gits error: {e}")));
                errors += 1;
            }
        }
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
