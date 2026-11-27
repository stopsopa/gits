use std::collections::BTreeSet;
use std::fs;
use std::io::Read;
use std::path::Path;

use crate::config;
use crate::events;
use crate::ops::{self, Storage, Temp};
use crate::socket::{Lazy, ENV_SOCKET};
use crate::util::{git_out, green, red, unique_sibling, yellow};
use crate::Ctx;

/*
 * gits crypt: the form in which ":e:" files are kept in the storage.
 *
 *   gits crypt status                   which files are stored plain / encrypted, and with which keys
 *   gits crypt encrypt --yes            stored plain      -> encrypted   (request "encode")
 *   gits crypt decrypt --yes            stored encrypted  -> plain       (request "decode")
 *   gits crypt rekey --yes              stored encrypted  -> the new keys of the server (request "rekey")
 *   gits crypt rekey --rewrap-only --yes                     only the key lines (request "rewrap")
 *
 * Scope: the project of the current directory (its .git/gits.sh), "all" (every project below
 * the current directory) or "--storage" (every file of the storage which is encrypted, whatever
 * config it belongs to; not for encrypt: only a config says what should be encrypted).
 *
 * Only the storage is changed (one clone, one commit, one push), local files are not touched.
 * gits knows nothing about keys: whether a file is encrypted is read from the file itself
 * (slots()), everything else is done by the encoder process behind GITS_ENCRYPTION_SOCKET.
 */

// how much of a file is looked at to tell binary from text, like git does
const SNIFF: usize = 8000;

// first line of every file encrypted by https://github.com/stopsopa/encrypt
const MAGIC: &str = "#ssenc1 ";
const SLOT: &str = "#slot ";

/**
 * Some(keys): the file is an encrypted one. None: it is not (or it doesn't exist).
 *
 * 1. a binary file (a NUL byte at its beginning) is never an encrypted one: encrypted output
 *    is always ASCII text, also when the input was binary
 * 2. a text file is an encrypted one when its first line is the header "#ssenc1 lines ..." /
 *    "#ssenc1 blob ..." and the lines after it are "#slot ..." (at least one): one per key
 *
 * keys: what opens the file, for a human: fingerprint of an ssh key ("SHA256:...") or "password".
 * No key is needed to read them.
 */
pub fn slots(file: &Path) -> Option<Vec<String>> {
    let mut head = Vec::new();
    fs::File::open(file)
        .ok()?
        .take(64 * 1024)
        .read_to_end(&mut head)
        .ok()?;
    slots_of(&head)
}

pub fn slots_of(head: &[u8]) -> Option<Vec<String>> {
    if head[..head.len().min(SNIFF)].contains(&0) {
        return None;
    }
    let text = String::from_utf8_lossy(head);
    let mut lines = text.lines();
    let header = lines.next()?;
    let mode = header.strip_prefix(MAGIC)?;
    if !(mode.starts_with("lines") || mode.starts_with("blob")) {
        return None;
    }
    let mut keys = Vec::new();
    for line in lines {
        let Some(slot) = line.strip_prefix(SLOT) else {
            break;
        };
        let mut words = slot.split_whitespace();
        keys.push(match words.next() {
            // "#slot ssh ssh-ed25519 SHA256:... ..."
            Some("ssh") => words
                .find(|w| w.starts_with("SHA256:"))
                .unwrap_or("ssh key")
                .to_string(),
            Some("pw") => "password".to_string(),
            Some(other) => other.to_string(),
            None => "?".to_string(),
        });
    }
    if keys.is_empty() {
        return None;
    }
    Some(keys)
}

#[derive(Clone, Copy, PartialEq)]
enum Verb {
    Status,
    Encrypt,
    Decrypt,
    Rekey,
}

#[derive(Clone, Copy, PartialEq)]
enum Scope {
    Project,
    All,
    Storage,
}

enum Form {
    Missing,
    Plain,
    Encrypted(Vec<String>),
}

const USAGE: &str = "usage: gits crypt status|encrypt|decrypt|rekey [all|--storage] [--rewrap-only] [--yes], see: gits --help";

fn commit_and_push(storage: &Storage, message: &str) -> Result<(), String> {
    events::fire("BEFORE_COMMIT", &[], &[])?;
    ops::sgit(&storage.root, &["add", "-A"], false)?;
    ops::sgit(&storage.root, &["commit", "-q", "-m", message], false)?;
    let commit = git_out(&storage.root, &["rev-parse", "HEAD"]).unwrap_or_default();
    let args = [commit.clone()];
    let vars = [("GITS_EVENT_COMMIT", commit)];
    events::fire("AFTER_COMMIT", &args, &vars)?;

    events::fire("BEFORE_PUSH", &args, &vars)?;
    ops::sgit(&storage.root, &["push", "origin", "HEAD"], false)?;
    events::fire("AFTER_PUSH", &args, &vars)
}

// every file of the clone, relative to its root, without .git
fn walk(root: &Path, dir: &Path, out: &mut BTreeSet<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        if kind.is_dir() {
            if dir == root && entry.file_name() == config::GIT_DIR {
                continue;
            }
            walk(root, &path, out);
        } else if kind.is_file() {
            if let Ok(relative) = path.strip_prefix(root) {
                out.insert(relative.to_string_lossy().to_string());
            }
        }
    }
}

// TARGETs of the ":e:" elements of one config
fn encrypted_targets(project: &config::Project, out: &mut BTreeSet<String>) {
    for entry in project.list.iter().filter(|e| e.encrypted) {
        out.insert(entry.target.clone());
    }
}

pub fn run(ctx: &Ctx, args: &[String], yes: bool) -> Result<i32, String> {
    let mut verb = None;
    let mut scope = Scope::Project;
    let mut rewrap = false;
    for arg in args {
        match arg.as_str() {
            "status" if verb.is_none() => verb = Some(Verb::Status),
            "encrypt" if verb.is_none() => verb = Some(Verb::Encrypt),
            "decrypt" if verb.is_none() => verb = Some(Verb::Decrypt),
            "rekey" if verb.is_none() => verb = Some(Verb::Rekey),
            "all" if scope == Scope::Project => scope = Scope::All,
            "--storage" if scope == Scope::Project => scope = Scope::Storage,
            "--rewrap-only" => rewrap = true,
            other => return Err(format!("gits crypt: unexpected argument >{other}<, {USAGE}")),
        }
    }
    let Some(verb) = verb else {
        return Err(USAGE.to_string());
    };
    if rewrap && verb != Verb::Rekey {
        return Err(format!("--rewrap-only is only for: gits crypt rekey, {USAGE}"));
    }
    if verb == Verb::Encrypt && scope == Scope::Storage {
        return Err(
            "gits crypt encrypt --storage: only a config (.git/gits.sh, its ':e:' elements) says which files \
             should be encrypted, the storage alone doesn't. Use: gits crypt encrypt all"
                .to_string(),
        );
    }
    let name = match verb {
        Verb::Status => "status",
        Verb::Encrypt => "encrypt",
        Verb::Decrypt => "decrypt",
        Verb::Rekey if rewrap => "rekey --rewrap-only",
        Verb::Rekey => "rekey",
    };

    // which files it is about: from the configs, before the storage is cloned
    let mut targets: BTreeSet<String> = BTreeSet::new();
    match scope {
        Scope::Project => encrypted_targets(&ops::load(ctx, false)?, &mut targets),
        Scope::All => {
            let found = config::find(&ctx.cwd)?;
            if found.is_empty() {
                println!("\n  nothing found\n");
                return Ok(0);
            }
            for project in &found {
                let dir = ctx.cwd.join(&project.dir);
                let dir = fs::canonicalize(&dir).unwrap_or(dir);
                let loaded = config::load(&dir, true)
                    .map_err(|e| format!("project >{}<: {e}", dir.display()))?;
                encrypted_targets(&loaded.project, &mut targets);
            }
        }
        Scope::Storage => {}
    }

    let temp = Temp::create(&ctx.cwd, false)?;
    let storage = Storage::clone(&ctx.source, &temp.path, false)?;

    if scope == Scope::Storage {
        let mut all = BTreeSet::new();
        walk(&storage.root, &storage.root, &mut all);
        targets = all
            .into_iter()
            .filter(|target| slots(&storage.root.join(target)).is_some())
            .collect();
    }

    let files: Vec<(String, Form)> = targets
        .into_iter()
        .map(|target| {
            let stored = storage.root.join(&target);
            let form = match slots(&stored) {
                Some(keys) => Form::Encrypted(keys),
                None if stored.is_file() => Form::Plain,
                None => Form::Missing,
            };
            (target, form)
        })
        .collect();

    let scope_text = match scope {
        Scope::Project => "':e:' files of this project",
        Scope::All => "':e:' files of all projects below the current directory",
        Scope::Storage => "every encrypted file of the storage",
    };

    if verb == Verb::Status {
        println!("\n{scope_text}, as they are stored:\n");
        let (mut encrypted, mut plain, mut missing) = (0, 0, 0);
        for (target, form) in &files {
            match form {
                Form::Encrypted(keys) => {
                    encrypted += 1;
                    println!("  {}  {target}  [{}]", green("encrypted"), keys.join(", "));
                }
                Form::Plain => {
                    plain += 1;
                    println!("  {}      {target}", yellow("plain"));
                }
                Form::Missing => {
                    missing += 1;
                    println!("  {}    {target}", red("missing"));
                }
            }
        }
        println!("\nencrypted: {encrypted}, plain: {plain}, not stored yet: {missing}\n");
        return Ok(0);
    }

    let todo: Vec<&String> = files
        .iter()
        .filter(|(_, form)| match verb {
            Verb::Encrypt => matches!(form, Form::Plain),
            _ => matches!(form, Form::Encrypted(_)),
        })
        .map(|(target, _)| target)
        .collect();

    if todo.is_empty() {
        println!(
            "{}",
            green(&format!("\n    gits crypt {name}: nothing to do ({scope_text})\n"))
        );
        return Ok(0);
    }

    if !yes {
        println!("\ngits crypt {name} would change in the storage ({scope_text}):\n");
        for target in &todo {
            println!("  {target}");
        }
        println!(
            "{}",
            red(&format!(
                "\ngits error: nothing was changed. If you are sure: gits crypt {} --yes",
                args.join(" ")
            ))
        );
        return Ok(1);
    }

    if ctx.socket.is_none() {
        return Err(format!(
            "gits crypt {name} needs the encoder process: env var {ENV_SOCKET} is not defined, \
             it has to point to its unix socket"
        ));
    }
    let mut enc = Lazy::new(ctx.socket.clone());

    for target in &todo {
        let stored = storage.root.join(target);
        // the result is written next to the file first: a failed request leaves the file as it was
        let other = unique_sibling(&stored);
        let done = match verb {
            Verb::Encrypt => {
                // the plain file is moved away: for the encoder there is no previous version at the output
                fs::rename(&stored, &other)
                    .map_err(|e| format!("can't move >{}<: {e}", stored.display()))?;
                let result = enc.get()?.encode(&other, &stored);
                if result.is_err() {
                    let _ = fs::remove_file(&stored);
                    let _ = fs::rename(&other, &stored);
                } else {
                    let _ = fs::remove_file(&other);
                }
                result
            }
            Verb::Decrypt => enc.get()?.decode(&stored, &other),
            _ => enc.get()?.rekey(&stored, &other, rewrap),
        };
        if let Err(e) = done {
            let _ = fs::remove_file(&other);
            return Err(format!(
                "gits crypt {name}: '{target}': {e}. Nothing was changed in the storage"
            ));
        }
        if verb != Verb::Encrypt {
            fs::rename(&other, &stored)
                .map_err(|e| format!("can't replace >{}<: {e}", stored.display()))?;
        }
        println!("{}", yellow(&format!("{name}: '{target}'")));
    }

    if storage.status()?.trim().is_empty() {
        println!("{}", green("\n    nothing changed in the storage\n"));
        return Ok(0);
    }

    let scope_name = match scope {
        Scope::Project => "project",
        Scope::All => "all",
        Scope::Storage => "storage",
    };
    commit_and_push(
        &storage,
        &format!("gits crypt {name} ({scope_name}, {} files)", todo.len()),
    )?;

    println!(
        "{}",
        green(&format!("\n    gits crypt {name}: {} files changed in the storage\n", todo.len()))
    );
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detection() {
        let ssh = b"#ssenc1 lines ws=1 pad=16\n#slot ssh ssh-ed25519 SHA256:abc AAAA BBBB\n#seal xyz\nline\n";
        assert_eq!(slots_of(ssh), Some(vec!["SHA256:abc".to_string()]));

        let two = b"#ssenc1 blob chunk=65536\n#slot ssh ssh-rsa SHA256:one x\n#slot pw argon2id m=8 t=1 p=1 x y\ndata\n";
        assert_eq!(
            slots_of(two),
            Some(vec!["SHA256:one".to_string(), "password".to_string()])
        );

        // plain text, also one which only mentions the header
        assert_eq!(slots_of(b"API_KEY=1\n"), None);
        assert_eq!(slots_of(b"#ssenc1 lines ws=1 pad=16\nno slot here\n"), None);
        assert_eq!(slots_of(b"# #ssenc1 lines\n#slot ssh x SHA256:a\n"), None);
        assert_eq!(slots_of(b""), None);
        // binary is never an encrypted file
        assert_eq!(slots_of(b"#ssenc1 lines ws=1 pad=16\n#slot ssh x SHA256:a\n\0"), None);
    }
}
