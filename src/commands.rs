use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use crate::config::{self, CONFIG, GIT_DIR, LEGACY, SEP_ENCRYPTED, SEP_PLAIN};
use crate::events;
use crate::menu;
use crate::ops::{remote_branch, url_for, Storage, Temp};
use crate::socket::Encoder;
use crate::util::{absolute, fetch, green, home, red, relative, unique_sibling, yellow};
use crate::Ctx;

pub const ENV_TEMPLATE: &str = "GITS_TEMPLATE";

const VARIABLE: &str = "GITS_TARGETDIR";
// in configs and templates written before the rename
const OLD_VARIABLE: &str = "GITSTORAGETARGETDIR";
const LIST: &str = "GITS_LIST";
const OLD_LIST: &str = "GITSTORAGELIST";

// inside double quotes of a shell script
fn shell_escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        if matches!(c, '"' | '\\' | '$' | '`') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

fn builtin_template(remote: &str) -> String {
    format!(
        r#"#!/bin/bash

# used in {remote}

{VARIABLE}=""

# "SOURCE::TARGET"    file stored as it is
# "SOURCE:e:TARGET"   file stored encrypted (needs env var GITS_ENCRYPTION_SOCKET)
#
# SOURCE  file on this machine: absolute path, path starting with ~/ or path relative to the
#         directory of this file (.git), so "../.env" is .env in the root of the project
# TARGET  path in the storage repository (env var GITS_SOURCE)
#
# gits add <file|directory> appends elements here
GITS_LIST=(
    "{CONFIG}::${VARIABLE}/{CONFIG}"
    # "../.env:e:${VARIABLE}/.env"
    # "xx.ts::${VARIABLE}/xx.ts"
    # "~/.zshrc::${VARIABLE}/.zshrc"
)
"#
    )
}

/**
 * The line GITS_TARGETDIR=... of a template replaced with the value of this project.
 * A template without such a line is an error: the config would not work.
 */
pub fn set_target_dir(text: &str, target_dir: &str) -> Result<String, String> {
    let mut done = false;
    let mut out = String::with_capacity(text.len() + target_dir.len());
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim_start();
        // a template written before the rename keeps the name it uses
        let name = [VARIABLE, OLD_VARIABLE]
            .into_iter()
            .find(|name| trimmed.starts_with(&format!("{name}=")));
        if let (false, Some(name)) = (done, name) {
            let indent = &line[..line.len() - trimmed.len()];
            let ending = if line.ends_with("\r\n") {
                "\r\n"
            } else if line.ends_with('\n') {
                "\n"
            } else {
                ""
            };
            out.push_str(&format!(
                "{indent}{name}=\"{}\"{ending}",
                shell_escape(target_dir)
            ));
            done = true;
        } else {
            out.push_str(line);
        }
    }
    if !done {
        return Err(format!(
            "there is no line starting with {VARIABLE}= in the template"
        ));
    }
    Ok(out)
}

fn next_steps() {
    println!(
        r#"
Now check the config:

  vi {GIT_DIR}/{CONFIG}

  gits add <file|directory>    register more files
  gits diff                    compare with the storage
  gits pull --yes              storage -> this machine
  gits push --yes              this machine -> storage
"#
    );
}

/**
 * Creates .git/gits.sh. In order: what the storage already has for this project (it was set up
 * on another machine), else the template from GITS_TEMPLATE, else the built-in template.
 */
pub fn init(ctx: &Ctx) -> Result<i32, String> {
    let dir = &ctx.cwd;
    if !dir.join(GIT_DIR).is_dir() {
        return Err(format!(
            "you have to execute it in the directory where {GIT_DIR} exists (root of a repository)"
        ));
    }

    let config = config::config_path(dir);
    if config.is_file() {
        println!(
            "{}",
            green(&format!(
                "{GIT_DIR}/{CONFIG} is already present - initialization not needed"
            ))
        );
        next_steps();
        return Ok(0);
    }
    if config::migrate(dir, false)? {
        next_steps();
        return Ok(0);
    }

    let remote = config::remote_origin(dir)?;
    let target_dir = config::target_dir_from_remote(&remote);

    let temp = Temp::create(dir, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;

    let stored = storage.root.join(&target_dir).join(CONFIG);
    let stored_legacy = storage.root.join(&target_dir).join(LEGACY);

    let written = |origin: &str, after: bool| {
        events::fire(
            if after { "AFTER_WRITE" } else { "BEFORE_WRITE" },
            &[config.display().to_string()],
            &[("GITS_EVENT_WRITE_ORIGIN", origin.to_string())],
        )
    };
    events::set("GITS_EVENT_PROJECT_DIR", dir.display().to_string());
    events::set("GITS_EVENT_CONFIG", config.display().to_string());
    events::set("GITS_TARGETDIR", target_dir.clone());

    if stored.is_file() {
        written("storage", false)?;
        restore(ctx, &stored, &config)?;
        written("storage", true)?;
        println!(
            "{}",
            green(&format!(
                "{GIT_DIR}/{CONFIG} restored from the storage: {target_dir}/{CONFIG}"
            ))
        );
    } else if stored_legacy.is_file() {
        let text = fs::read_to_string(&stored_legacy)
            .map_err(|e| format!("can't read >{}<: {e}", stored_legacy.display()))?;
        written("storage", false)?;
        fs::write(&config, config::migrate_content(&text))
            .map_err(|e| format!("can't write >{}<: {e}", config.display()))?;
        written("storage", true)?;
        println!(
            "{}",
            green(&format!(
                "{GIT_DIR}/{CONFIG} restored from the storage: {target_dir}/{LEGACY} (migrated)"
            ))
        );
    } else {
        let template = match &ctx.template {
            Some(source) => {
                let bytes = fetch(source)
                    .map_err(|e| format!("template {ENV_TEMPLATE}=>{source}<: {e}"))?;
                String::from_utf8(bytes)
                    .map_err(|_| format!("template {ENV_TEMPLATE}=>{source}< is not a text file"))?
            }
            None => builtin_template(&remote),
        };
        let text = set_target_dir(&template, &target_dir).map_err(|e| match &ctx.template {
            Some(source) => format!("template {ENV_TEMPLATE}=>{source}<: {e}"),
            None => e,
        })?;
        let origin = if ctx.template.is_some() {
            "template"
        } else {
            "built-in"
        };
        written(origin, false)?;
        fs::write(&config, text).map_err(|e| format!("can't write >{}<: {e}", config.display()))?;
        written(origin, true)?;
        println!(
            "{}",
            green(&format!(
                "{GIT_DIR}/{CONFIG} generated ({}), now you can add some files to store",
                match &ctx.template {
                    Some(source) => format!("template {source}"),
                    None => "built-in template".to_string(),
                }
            ))
        );
    }

    next_steps();
    Ok(0)
}

// the stored config can be an encrypted one ("gits.sh:e:...")
fn restore(ctx: &Ctx, stored: &Path, config: &Path) -> Result<(), String> {
    let copy = |from: &Path| {
        fs::copy(from, config)
            .map(|_| ())
            .map_err(|e| format!("can't write >{}<: {e}", config.display()))
    };

    let Some(socket) = &ctx.socket else {
        let head = fs::read(stored).unwrap_or_default();
        if head.starts_with(b"#ssenc") {
            return Err(format!(
                "the config in the storage >{}< is encrypted, define env var {} to restore it",
                stored.display(),
                crate::socket::ENV_SOCKET
            ));
        }
        return copy(stored);
    };

    let plain = unique_sibling(stored);
    let result = match Encoder::connect(socket)?.decode(stored, &plain) {
        Ok(()) => copy(&plain),
        Err(e) if e.malformed() => copy(stored),
        Err(e) => Err(format!("can't decrypt the config from the storage: {e}")),
    };
    let _ = fs::remove_file(&plain);
    result
}

// all regular files below a directory, sorted; .git and node_modules are not entered
fn files_below(dir: &Path, out: &mut Vec<PathBuf>) {
    let mut entries: Vec<_> = match fs::read_dir(dir) {
        Ok(e) => e.flatten().collect(),
        Err(_) => return,
    };
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        let name = entry.file_name();
        if kind.is_dir() {
            if name == GIT_DIR || name == "node_modules" {
                continue;
            }
            files_below(&entry.path(), out);
        } else if kind.is_file() {
            out.push(entry.path());
        }
    }
}

struct Block {
    // index of the line with the closing ")"
    end: usize,
    // SOURCE of every element, as an absolute path
    sources: HashSet<PathBuf>,
    indent: String,
    // "$GITS_TARGETDIR/" or "${GITS_TARGETDIR}/"
    variable: String,
}

// "    "SOURCE::TARGET"   " -> SOURCE::TARGET
fn quoted(line: &str) -> Option<&str> {
    let trimmed = line.trim();
    let quote = trimmed.chars().next().filter(|c| *c == '"' || *c == '\'')?;
    let rest = &trimmed[1..];
    let end = rest.rfind(quote)?;
    Some(&rest[..end])
}

fn most_common(counts: HashMap<String, usize>, default: &str) -> String {
    counts
        .into_iter()
        .max_by(|a, b| a.1.cmp(&b.1).then(b.0.cmp(&a.0)))
        .map(|(k, _)| k)
        .unwrap_or_else(|| default.to_string())
}

fn parse_block(lines: &[&str], project_dir: &Path) -> Result<Block, String> {
    let start = lines
        .iter()
        .position(|l| {
            let l = l.trim_start();
            l.starts_with(&format!("{LIST}=(")) || l.starts_with(&format!("{OLD_LIST}=("))
        })
        .ok_or_else(|| format!("there is no line starting with {LIST}=( in the config"))?;
    let end = lines
        .iter()
        .enumerate()
        .skip(start + 1)
        .find(|(_, l)| l.trim_start().starts_with(')'))
        .map(|(i, _)| i)
        .ok_or_else(|| {
            "can't find the end of GITS_LIST in the config: a line starting with ) is expected, one element per line"
                .to_string()
        })?;

    let mut sources = HashSet::new();
    let mut indents: HashMap<String, usize> = HashMap::new();
    let mut variables: HashMap<String, usize> = HashMap::new();

    for line in &lines[start + 1..end] {
        let Some(element) = quoted(line) else {
            continue;
        };
        let Ok((source, _, target)) = config::split_entry(element) else {
            continue;
        };
        sources.insert(config::resolve_source(&source, project_dir));
        let indent = &line[..line.len() - line.trim_start().len()];
        *indents.entry(indent.to_string()).or_default() += 1;
        for form in [
            format!("${VARIABLE}/"),
            format!("${{{VARIABLE}}}/"),
            format!("${OLD_VARIABLE}/"),
            format!("${{{OLD_VARIABLE}}}/"),
        ] {
            if target.starts_with(&form) {
                *variables.entry(form).or_default() += 1;
            }
        }
    }

    Ok(Block {
        end,
        sources,
        indent: most_common(indents, "    "),
        // nothing to copy the style from: the variable the config defines
        variable: most_common(
            variables,
            &format!(
                "${}/",
                if lines
                    .iter()
                    .any(|l| l.trim_start().starts_with(&format!("{OLD_VARIABLE}=")))
                {
                    OLD_VARIABLE
                } else {
                    VARIABLE
                }
            ),
        ),
    })
}

/**
 * (SOURCE, TARGET without the variable) for a file, both the way a person would write them:
 *   inside the project    relative to .git      ->  path inside the project (".git/" dropped: git can't store it)
 *   inside home           ~/path                ->  path inside home
 *   elsewhere             /absolute/path        ->  the same without the first /
 */
fn source_and_target(file: &Path, project_dir: &Path) -> (String, String) {
    if let Ok(inside) = file.strip_prefix(project_dir) {
        let source = relative(file, &project_dir.join(GIT_DIR));
        let target = inside.strip_prefix(GIT_DIR).unwrap_or(inside);
        return (
            source.to_string_lossy().to_string(),
            target.to_string_lossy().to_string(),
        );
    }
    if let Some(h) = home() {
        if let Ok(inside) = file.strip_prefix(&h) {
            let inside = inside.to_string_lossy().to_string();
            return (format!("~/{inside}"), inside);
        }
    }
    let path = file.to_string_lossy().to_string();
    let target = path.trim_start_matches('/').to_string();
    (path, target)
}

// the files which are not in GITS_LIST yet (each once, in the given order) + how many were dropped
pub fn not_registered(
    text: &str,
    files: &[PathBuf],
    project_dir: &Path,
) -> Result<(Vec<PathBuf>, usize), String> {
    let lines: Vec<&str> = text.split('\n').collect();
    let mut block = parse_block(&lines, project_dir)?;
    let fresh: Vec<PathBuf> = files
        .iter()
        .filter(|f| block.sources.insert((*f).clone()))
        .cloned()
        .collect();
    let dropped = files.len() - fresh.len();
    Ok((fresh, dropped))
}

// a file the way it is shown in the list of "gits add": relative to the project, ~/..., or absolute
fn shown(file: &Path, project_dir: &Path) -> String {
    if let Ok(inside) = file.strip_prefix(project_dir) {
        return inside.to_string_lossy().to_string();
    }
    source_and_target(file, project_dir).0
}

/**
 * Content of the config with the files appended to GITS_LIST + the lines which were added.
 * files: (file, encrypted): "SOURCE:e:TARGET" when true, "SOURCE::TARGET" when not.
 */
pub fn add_to_config(
    text: &str,
    files: &[(PathBuf, bool)],
    project_dir: &Path,
) -> Result<(String, Vec<String>), String> {
    let mut lines: Vec<&str> = text.split('\n').collect();
    let mut block = parse_block(&lines, project_dir)?;

    let mut added: Vec<String> = Vec::new();
    for (file, encrypt) in files {
        if !block.sources.insert(file.clone()) {
            continue;
        }
        let separator = if *encrypt { SEP_ENCRYPTED } else { SEP_PLAIN };
        let (source, target) = source_and_target(file, project_dir);
        added.push(format!(
            "{}\"{}{separator}{}{}\"",
            block.indent,
            shell_escape(&source),
            block.variable,
            shell_escape(&target)
        ));
    }

    let at = block.end;
    for (i, line) in added.iter().enumerate() {
        lines.insert(at + i, line.as_str());
    }
    Ok((lines.join("\n"), added))
}

/**
 * Registers files in .git/gits.sh, nothing else: the result is there to be reviewed.
 *
 * In a terminal the found files are shown first as a list (src/menu.rs) where each one can be
 * ticked, and marked as encrypted; the config is written after ctrl+enter. At the beginning
 * everything is ticked, with -e also as encrypted.
 * Without a terminal (a pipe, a script) and with --yes there is no list: all the found files
 * are added, with -e all of them as encrypted.
 */
pub fn add(ctx: &Ctx, paths: &[String], encrypt: bool, yes: bool) -> Result<i32, String> {
    if paths.is_empty() {
        return Err(
            "usage: gits add [-e] [--yes] <file|directory> [<file|directory> ...]".to_string(),
        );
    }

    let dir = &ctx.cwd;
    let config = config::config_path(dir);
    if !config.is_file() && !config::migrate(dir, false)? {
        return Err(format!(
            "config >{}< doesn't exist, create it with: gits init",
            config.display()
        ));
    }

    let mut files: Vec<PathBuf> = Vec::new();
    for path in paths {
        let full = absolute(&crate::util::expand_tilde(path), dir);
        if full.is_file() {
            files.push(full);
        } else if full.is_dir() {
            files_below(&full, &mut files);
        } else {
            return Err(format!(">{path}< is neither a file nor a directory"));
        }
    }

    let text = fs::read_to_string(&config)
        .map_err(|e| format!("can't read >{}<: {e}", config.display()))?;
    let found = files.len();
    let (fresh, registered) =
        not_registered(&text, &files, dir).map_err(|e| format!("{e} (>{}<)", config.display()))?;

    if fresh.is_empty() {
        println!("\n  nothing added: all {found} file(s) are already in {GIT_DIR}/{CONFIG}\n");
        return Ok(0);
    }

    let chosen: Vec<(PathBuf, bool)> = if !yes && menu::interactive() {
        let rows = fresh
            .iter()
            .map(|f| (shown(f, dir), true, encrypt))
            .collect();
        match menu::select(rows, registered)? {
            menu::Outcome::Done(picked) => picked
                .into_iter()
                .map(|(index, encrypted)| (fresh[index].clone(), encrypted))
                .collect(),
            menu::Outcome::Cancelled => {
                println!("\n  nothing added: the list was left without ctrl+enter\n");
                return Ok(1);
            }
            menu::Outcome::Interrupted => {
                println!("\n  nothing added: interrupted\n");
                return Ok(130);
            }
        }
    } else {
        fresh.into_iter().map(|f| (f, encrypt)).collect()
    };

    let (changed, added) =
        add_to_config(&text, &chosen, dir).map_err(|e| format!("{e} (>{}<)", config.display()))?;

    events::set("GITS_EVENT_PROJECT_DIR", dir.display().to_string());
    events::set("GITS_EVENT_CONFIG", config.display().to_string());
    let write_args = [config.display().to_string()];
    let write_vars = [("GITS_EVENT_WRITE_ORIGIN", added.len().to_string())];
    events::fire("BEFORE_WRITE", &write_args, &write_vars)?;
    fs::write(&config, changed).map_err(|e| format!("can't write >{}<: {e}", config.display()))?;
    events::fire("AFTER_WRITE", &write_args, &write_vars)?;

    println!(
        "\n  added lines: {}\n  to file {GIT_DIR}/{CONFIG}\n",
        added.len()
    );
    for line in &added {
        println!("{line}");
    }
    println!("\n  only the config was changed, review it and then: gits diff, gits push --yes\n");
    Ok(0)
}

pub fn find(ctx: &Ctx) -> Result<i32, String> {
    for project in config::find(&ctx.cwd)? {
        println!("{}", project.dir);
    }
    Ok(0)
}

fn storage_note() {
    println!(
        "{}",
        yellow(&format!(
            "the storage still has the old {LEGACY}: after the next 'gits push --yes' ({CONFIG} gets stored) remove it from the storage by hand"
        ))
    );
}

pub fn migrate(ctx: &Ctx, args: &[String]) -> Result<i32, String> {
    match args {
        [] => {
            if config::migrate(&ctx.cwd, false)? {
                storage_note();
                return Ok(0);
            }
            let config = config::config_path(&ctx.cwd);
            if config.is_file() {
                // a gits.sh written before the variables were renamed (it works as it is, too)
                let text = fs::read_to_string(&config)
                    .map_err(|e| format!("can't read >{}<: {e}", config.display()))?;
                let renamed = config::rename_variables(&text);
                if renamed != text {
                    fs::write(&config, renamed)
                        .map_err(|e| format!("can't write >{}<: {e}", config.display()))?;
                    println!(
                        "{}",
                        yellow(&format!(
                            "{GIT_DIR}/{CONFIG}: variables renamed (GITSTORAGETARGETDIR -> GITS_TARGETDIR, GITSTORAGELIST -> GITS_LIST)"
                        ))
                    );
                    return Ok(0);
                }
                println!("nothing to migrate: {GIT_DIR}/{CONFIG} is already here");
                return Ok(0);
            }
            Err(format!(
                "nothing to migrate: there is no {GIT_DIR}/{LEGACY} in the current directory"
            ))
        }
        [all] if all == "all" => {
            let found: Vec<_> = config::find(&ctx.cwd)?
                .into_iter()
                .filter(|f| f.legacy)
                .collect();
            if found.is_empty() {
                println!("\n  nothing found: no {GIT_DIR}/{LEGACY} below the current directory\n");
                return Ok(0);
            }
            let mut errors = 0;
            for project in &found {
                if let Err(e) = config::migrate(&absolute(Path::new(&project.dir), &ctx.cwd), false)
                {
                    errors += 1;
                    println!("{}", red(&format!("gits error: {e}")));
                }
            }
            println!();
            println!(
                "{}",
                green(&format!("COUNT_SUCCESS : {}", found.len() - errors))
            );
            println!("{}", red(&format!("COUNT_ERROR   : {errors}")));
            println!();
            storage_note();
            Ok(if errors > 0 { 1 } else { 0 })
        }
        _ => Err("usage: gits migrate | gits migrate all".to_string()),
    }
}

// prints the procedure, changes nothing
pub fn mv(ctx: &Ctx, args: &[String]) -> Result<i32, String> {
    let [old, new] = args else {
        return Err(
            "usage: gits move <old remote> <new remote>, e.g. gits move git@xxx:project/source-repo.git git@yyy:project/target-repo.git"
                .to_string(),
        );
    };
    let from = config::target_dir_from_remote(old);
    let to = config::target_dir_from_remote(new);
    let source = &ctx.source;
    let branch = remote_branch(source, &ctx.cwd);
    let url_from = url_for(source, &branch, &from);
    let url_to = url_for(source, &branch, &to);
    let from_sh = shell_escape(&from);
    let to_sh = shell_escape(&to);
    let new_sh = shell_escape(new);
    let source_sh = shell_escape(source);
    let message = shell_escape(&format!("gits move {old} {new}"));

    println!(
        r#"
The directory of the project in the storage has to follow the url of its remote 'origin'.

  from: {from}
        {url_from}
  to:   {to}
        {url_to}

Nothing was changed. The procedure:

1. Rename the directory in the storage. Paste in a terminal:

rm -rf ____temporary_directory_remove_later
mkdir ____temporary_directory_remove_later
cd ____temporary_directory_remove_later
git clone "{source_sh}" .
git mv "{from_sh}" "{to_sh}"
git commit -m "{message}"
git push
cd ..
rm -rf ____temporary_directory_remove_later

2. In the project, point the repository to the new remote (when it is not done yet):

git remote set-url origin "{new_sh}"

3. In the project, in {GIT_DIR}/{CONFIG} change

    {VARIABLE}="{from}"

   to

    {VARIABLE}="{to}"

4. Check and store the changed config:

gits diff          # only {CONFIG} should differ: the line from step 3
gits push --yes
"#
    );
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn template_target_dir() {
        let text = "#!/bin/bash\n  GITS_TARGETDIR=\"old\"\nGITS_LIST=(\n)\n";
        assert_eq!(
            set_target_dir(text, "git@github.com:o__r.git").unwrap(),
            "#!/bin/bash\n  GITS_TARGETDIR=\"git@github.com:o__r.git\"\nGITS_LIST=(\n)\n"
        );
        assert!(set_target_dir("GITS_LIST=(\n)\n", "x").is_err());
        // only the definition, not the places where it is used
        let built = set_target_dir(&builtin_template("git@github.com:o/r.git"), "D").unwrap();
        assert!(built.contains("\nGITS_TARGETDIR=\"D\"\n"));
        assert!(built.contains("\"gits.sh::$GITS_TARGETDIR/gits.sh\""));
    }

    #[test]
    fn add_keeps_everything_else() {
        let text = "#!/bin/bash\nGITS_TARGETDIR=\"d\"\n\nGITS_LIST=(\n  \"gits.sh::${GITS_TARGETDIR}/gits.sh\"\n\n  # comment\n  \"../.env::${GITS_TARGETDIR}/.env\"\n)\n\necho after\n";
        let project = Path::new("/w/p");
        let paths = vec![
            PathBuf::from("/w/p/.env"),
            PathBuf::from("/w/p/dir/a b.txt"),
            PathBuf::from("/w/p/.git/xx.ts"),
            PathBuf::from("/elsewhere/c.txt"),
        ];
        let files: Vec<(PathBuf, bool)> = paths.iter().map(|p| (p.clone(), false)).collect();

        // what the list of "gits add" is made of: .env is registered already
        let (fresh, dropped) = not_registered(text, &paths, project).unwrap();
        assert_eq!(fresh, paths[1..].to_vec());
        assert_eq!(dropped, 1);
        assert_eq!(shown(&paths[1], project), "dir/a b.txt");
        assert_eq!(shown(&paths[2], project), ".git/xx.ts");
        assert_eq!(shown(&paths[3], project), "/elsewhere/c.txt");

        let (changed, added) = add_to_config(text, &files, project).unwrap();
        assert_eq!(
            added,
            vec![
                "  \"../dir/a b.txt::${GITS_TARGETDIR}/dir/a b.txt\"",
                "  \"xx.ts::${GITS_TARGETDIR}/xx.ts\"",
                "  \"/elsewhere/c.txt::${GITS_TARGETDIR}/elsewhere/c.txt\"",
            ]
        );
        assert_eq!(
            changed,
            "#!/bin/bash\nGITS_TARGETDIR=\"d\"\n\nGITS_LIST=(\n  \"gits.sh::${GITS_TARGETDIR}/gits.sh\"\n\n  # comment\n  \"../.env::${GITS_TARGETDIR}/.env\"\n  \"../dir/a b.txt::${GITS_TARGETDIR}/dir/a b.txt\"\n  \"xx.ts::${GITS_TARGETDIR}/xx.ts\"\n  \"/elsewhere/c.txt::${GITS_TARGETDIR}/elsewhere/c.txt\"\n)\n\necho after\n"
        );

        // second time: nothing to add
        let (again, added) = add_to_config(&changed, &files, project).unwrap();
        assert!(added.is_empty());
        assert_eq!(again, changed);
    }

    #[test]
    fn add_encrypted_and_defaults() {
        let text = "GITS_LIST=(\n)\n";
        // encryption is decided per file
        let files = [
            (PathBuf::from("/w/p/.env"), true),
            (PathBuf::from("/w/p/plain.txt"), false),
        ];
        let (changed, _) = add_to_config(text, &files, Path::new("/w/p")).unwrap();
        assert_eq!(
            changed,
            "GITS_LIST=(\n    \"../.env:e:$GITS_TARGETDIR/.env\"\n    \"../plain.txt::$GITS_TARGETDIR/plain.txt\"\n)\n"
        );
        assert!(add_to_config("nothing here\n", &[], Path::new("/w/p")).is_err());
        assert!(add_to_config("GITS_LIST=( \"a::b\" )\n", &[], Path::new("/w/p")).is_err());
    }
}
