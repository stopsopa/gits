mod cli;
mod commands;
mod config;
mod crypt;
mod events;
mod menu;
mod ops;
mod socket;
mod update;
mod util;

use std::path::PathBuf;

use util::{env_any, env_named, red, yellow};

// the pushed tag for a release, "dev" for every other build (build.rs)
pub const VERSION: &str = env!("GITS_BUILD_VERSION");

pub const ENV_SOURCE: &str = "GITS_SOURCE";

// what every command needs
pub struct Ctx {
    // directory gits was started in
    pub cwd: PathBuf,
    // GITS_SOURCE: the storage repository
    pub source: String,
    // GITS_ENCRYPTION_SOCKET
    pub socket: Option<String>,
    // GITS_TEMPLATE
    pub template: Option<String>,
}

struct Var {
    name: &'static str,
    default: &'static str,
    required: bool,
    // what happens when there is neither a value nor a default
    unset: &'static str,
    about: &'static str,
}

const VARS: [Var; 7] = [
    Var {
        name: ENV_SOURCE,
        default: "",
        required: true,
        unset: "MISSING (required)",
        about: "the storage: git repository where files are kept, e.g. git@github.com:stopsopa/gitstorage.git",
    },
    Var {
        name: config::ENV_SHELL,
        default: config::DEFAULT_SHELL,
        required: false,
        unset: "",
        about: "shell which executes .git/gits.sh (the config is a shell script) and the scripts of events",
    },
    Var {
        name: socket::ENV_SOCKET,
        default: "",
        required: false,
        unset: "(not used: elements SOURCE:e:TARGET can't be handled)",
        about: "unix socket of the encoder process. Not defined: :e: is ignored, files are stored as they are",
    },
    Var {
        name: commands::ENV_TEMPLATE,
        default: "",
        required: false,
        unset: "(built-in template)",
        about: "url or file: template of .git/gits.sh for 'gits init' (default: built-in)",
    },
    Var {
        name: ops::ENV_PULL_TO_SYNC,
        default: "",
        required: false,
        unset: "(not used: a fresh clone in a directory with a random name, removed at the end)",
        about: "directory (absolute or ~/...) where the clone of the storage is kept between runs: \
                only what is new is fetched instead of cloning everything every time",
    },
    Var {
        name: update::ENV_RELEASES,
        default: update::RELEASES,
        required: false,
        unset: "",
        about: "where 'gits --update' takes releases from (url or directory)",
    },
    Var {
        name: update::ENV_CONFIRM,
        default: "true",
        required: false,
        unset: "",
        about: "false: 'gits --update' doesn't ask before replacing the binary",
    },
];

fn pad(text: &str, width: usize) -> String {
    format!(
        "{text}{}",
        " ".repeat(width.saturating_sub(text.chars().count()))
    )
}

/**
 * First column of the table of env vars: the name with the value exactly as it is in the
 * environment, so the three cases can be told apart:
 *
 *   NAME (not defined)
 *   NAME="" (empty)
 *   NAME="value"          quoted: spaces at the ends are visible
 */
fn in_shell(name: &str) -> String {
    match std::env::var_os(name) {
        None => format!("{name} (not defined)"),
        Some(value) if value.is_empty() => format!("{name}=\"\" (empty)"),
        Some(value) => format!("{name}=\"{}\"", value.to_string_lossy()),
    }
}

enum Row {
    // a line between groups of variables
    Title(&'static str),
    // variable with its value in the shell | default | the value gits uses | printed in red
    Var(String, String, String, bool),
}

/**
 * Every env var gits reacts to: the ones with a meaning of their own, the old names, the
 * variables of other programs gits looks at, and one variable per lifecycle event.
 */
fn env_rows() -> Vec<Row> {
    let mut rows = vec![Row::Title("gits itself")];

    for v in VARS.iter() {
        let named = env_named(v.name);
        let used = match &named {
            Some((value, from)) if from == v.name => value.clone(),
            Some((value, from)) => format!("{value} (from {from})"),
            None if !v.default.is_empty() => v.default.to_string(),
            None => v.unset.to_string(),
        };
        let default = match (v.default.is_empty(), v.required) {
            (false, _) => v.default.to_string(),
            (true, true) => "(none, required)".to_string(),
            (true, false) => "(none)".to_string(),
        };
        rows.push(Row::Var(
            in_shell(v.name),
            default,
            used,
            v.required && named.is_none(),
        ));
    }

    rows.push(Row::Title(
        "names from before the rename, read only when the new one is not defined",
    ));
    for v in VARS.iter() {
        let Some(old) = util::old_name(v.name) else {
            continue;
        };
        let used = match (util::env(v.name), util::env(old)) {
            (Some(_), Some(_)) => format!("(ignored: {} is defined)", v.name),
            (None, Some(value)) => format!("{value} (as {})", v.name),
            (_, None) => "(not used)".to_string(),
        };
        rows.push(Row::Var(in_shell(old), "(none)".to_string(), used, false));
    }

    rows.push(Row::Title("of other programs, gits looks at them too"));
    rows.push(Row::Var(
        in_shell("HOME"),
        "(none)".to_string(),
        match util::home() {
            Some(home) => home.display().to_string(),
            None => "(none: ~/ in paths is not expanded)".to_string(),
        },
        false,
    ));
    rows.push(Row::Var(
        in_shell("NO_COLOR"),
        "(none)".to_string(),
        // defined with any value, also an empty one
        if std::env::var_os("NO_COLOR").is_some() {
            "no colors".to_string()
        } else {
            "colors, when the output is a terminal".to_string()
        },
        false,
    ));

    rows.push(Row::Title(
        "lifecycle events: the value is the path of a script (see: gits events, LIFECYCLE.md)",
    ));
    let nested = util::env(events::ENV_RUNNING).is_some();
    rows.push(Row::Var(
        in_shell(events::ENV_RUNNING),
        "(none)".to_string(),
        if nested {
            "no script of any event runs".to_string()
        } else {
            "(scripts of events run)".to_string()
        },
        false,
    ));
    rows.push(Row::Var(
        in_shell(events::ENV_START),
        "(none)".to_string(),
        match util::env(events::ENV_START) {
            Some(_) if nested => format!("(ignored: {} is defined)", events::ENV_RUNNING),
            Some(value) => util::expand_tilde(&value).display().to_string(),
            None => "(no script)".to_string(),
        },
        false,
    ));
    rows.push(Row::Var(
        in_shell(events::ENV_EXIT),
        "(none)".to_string(),
        match util::env(events::ENV_EXIT) {
            Some(_) if nested => format!("(ignored: {} is defined)", events::ENV_RUNNING),
            Some(value) => util::expand_tilde(&value).display().to_string(),
            None => "(no script)".to_string(),
        },
        false,
    ));
    for (name, replaceable) in events::variables() {
        let default = if replaceable {
            "built-in: events/defaults/FIND.sh"
        } else {
            "(none)"
        };
        let used = match util::env(&name) {
            Some(_) if nested => format!("(ignored: {} is defined)", events::ENV_RUNNING),
            // the path as gits will look for it: ~/ expanded
            Some(value) => util::expand_tilde(&value).display().to_string(),
            None if replaceable => "the built-in script".to_string(),
            None => "(no script)".to_string(),
        };
        rows.push(Row::Var(in_shell(&name), default.to_string(), used, false));
    }
    rows
}

// variable with its value in the shell | default | the value gits uses
fn env_table() -> String {
    let rows = env_rows();
    let header = ["variable, and its value in the shell", "default", "used"];
    let mut widths = header.map(|h| h.len());
    for row in &rows {
        if let Row::Var(shell, default, _, _) = row {
            widths[0] = widths[0].max(shell.chars().count());
            widths[1] = widths[1].max(default.chars().count());
        }
    }

    let line = |cells: [&str; 3]| -> String {
        format!(
            "  {} | {} | {}",
            pad(cells[0], widths[0]),
            pad(cells[1], widths[1]),
            cells[2]
        )
    };

    let mut out = String::new();
    out.push_str(&line(header));
    out.push('\n');
    out.push_str(&format!(
        "  {}-|-{}-|-{}\n",
        "-".repeat(widths[0]),
        "-".repeat(widths[1]),
        "-".repeat(header[2].len())
    ));
    for row in &rows {
        match row {
            Row::Title(title) => out.push_str(&format!("\n  # {title}\n")),
            Row::Var(shell, default, used, missing) => {
                let text = line([shell, default, used]);
                if *missing {
                    out.push_str(&red(&text));
                } else {
                    out.push_str(&text);
                }
                out.push('\n');
            }
        }
    }
    out.push_str(
        "\n  first column: (not defined), \"\" (empty) or the value, exactly as it is in the shell.\n  \
         A value which is empty or only spaces counts as not defined (besides NO_COLOR).\n\n",
    );
    let width = VARS.iter().map(|v| v.name.len()).max().unwrap_or(0);
    for var in VARS.iter() {
        out.push_str(&format!("  {}  {}\n", pad(var.name, width), var.about));
    }
    out
}

fn help() -> String {
    #[allow(non_snake_case)]
    let LIST_MODES: String = commands::list_modes()
        .iter()
        .map(|mode| {
            let default = if mode == commands::LIST_MODE_DEFAULT {
                "   (default: the search of gits state)"
            } else {
                ""
            };
            format!("                          {mode}{default}\n")
        })
        .collect();
    let mut out = format!(
        r#"
gits {VERSION}

Keeps files which don't belong to the repository of a project (.env, local configs, dotfiles)
in one private git repository, the storage. Each project describes its files in .git/gits.sh:

    GITS_TARGETDIR="git@github.com:owner__repo.git"     # directory of the project in the storage
    GITS_LIST=(
        "gits.sh::$GITS_TARGETDIR/gits.sh"              # "SOURCE::TARGET"    stored as it is
        "../.env:e:$GITS_TARGETDIR/.env"                # "SOURCE:e:TARGET"   stored encrypted
        "~/.zshrc::$GITS_TARGETDIR/.zshrc"
    )

    SOURCE  file on this machine: absolute, starting with ~/, or relative to .git
    TARGET  path in the storage

In any directory:

  gits state            find all projects below the current directory (.git/gits.sh, .git/gitstorage-config.sh)
                        and say for each whether its files are in sync with the storage.
                        Prints 'cd "<project>"' + 'gits diff' for each, ready to paste.
  gits find             only list the directories of those projects, one per line
  gits list             the same projects with absolute paths, one per line and nothing else,
                        for pipes: gits list | /bin/bash script.sh
                        Works without GITS_SOURCE. Runs no lifecycle scripts besides the search.
  gits list --mode <variable>
                        which variable provides the script of the search (not defined: the
                        built-in search, events/defaults/FIND.sh):
{LIST_MODES}  gits migrate all      .git/gitstorage-config.sh -> .git/gits.sh in all projects below the current directory

In the root of a project (the directory with .git):

  gits init             create .git/gits.sh: from the storage when it has one for this project,
                        else from the template
  gits diff             what differs between local files and the storage (git diff). Exit code 1 when not in sync
  gits isinsync         the same check, only the exit code: 0 in sync, 1 not in sync, 2 error
  gits push --yes       local files -> storage (commit and push). Without --yes nothing is changed
  gits pull --yes       storage -> local files (they are overwritten). Without --yes nothing is changed
  gits url              web address of the directory of this project in the storage
  gits add [-e] <file|directory> ...
                        register files in .git/gits.sh (only the config is changed).
                        In a terminal the found files are listed first: tick which ones to add
                        and which of them as encrypted, ctrl+enter writes them.
                        Without the list, everything found: echo "" | gits add ...
                        (the list is shown only when stdin is a terminal)
                        Paths can also come from stdin, one file per line, no list then:
                          find . -name '.env*' | gits add
                          find config -type f | gits add -e
                        -e: register the files as encrypted elements, SOURCE:e:TARGET instead
                        of SOURCE::TARGET: push encrypts such a file before it is stored, pull
                        and diff decrypt it (see "Encryption" below). With the list -e
                        only ticks the box "enc" of every row at the start
  gits move <old remote> <new remote>
                        print the procedure of renaming the directory in the storage after
                        the remote 'origin' of the project changed
  gits migrate          .git/gitstorage-config.sh -> .git/gits.sh (also done automatically when needed)

Encryption (elements SOURCE:e:TARGET):

  gits never encrypts by itself: it sends requests to the encoder process listening on the
  unix socket GITS_ENCRYPTION_SOCKET. Which key encrypts is the business of that process.

  GITS_ENCRYPTION_SOCKET not defined, or nobody answers on that socket:
                        ':e:' is ignored, files are transported as they are (like '::').
                        Only a file which is already stored encrypted is an error.
                        push and pull list the ':e:' files first, and in a terminal they wait:
                        Enter goes on without encryption, Esc stops. Without a terminal
                        (stdin is not one) there is only the warning.
                        A config without ':e:' elements: nothing of this is said or asked.
  GITS_ENCRYPTION_SOCKET defined:
                        push encrypts, pull and diff decrypt. A ':e:' file which is still
                        stored plain is used as it is, and encrypted by the next push.

  The form of what is already in the storage (only the storage is changed: one commit, one push):

  gits crypt status            every ':e:' file: stored encrypted (and the keys which open it:
                               fingerprints of ssh keys), plain, or not stored yet. Needs no socket
  gits crypt encrypt --yes     ':e:' files stored plain -> encrypted
  gits crypt decrypt --yes     files stored encrypted -> plain; the rest is left as it is
  gits crypt rekey --yes       files stored encrypted -> the new keys of the encoder process
                               (it has to be started with them), everything is encrypted again
  gits crypt rekey --rewrap-only --yes
                               only the key lines at the top of each file change

    scope, after the verb:
      (nothing)    the ':e:' elements of this project (.git/gits.sh)
      all          the ':e:' elements of every project below the current directory
      --storage    every file of the storage which is encrypted, whatever config it belongs to,
                   also projects which are not on this machine (not for encrypt)
    Without --yes: only the list of files which would change, exit code 1.
    A file is an encrypted one when it is text and starts with the lines '#ssenc1 ...' + '#slot ...'.

Everything which needs the storage clones it to a directory with a random name in the current
directory and removes it at the end.

The tool itself:

  gits --help
  gits --version
  gits --update            update to the latest release
  gits --update <tag>      install the given release (also an older one), e.g. v0.1.0
  gits --update --check    only say whether there is something newer, change nothing

Lifecycle events: your scripts run between the stages of every command (see LIFECYCLE.md)

  gits events              every event of every command, and which ones have a script right now
  gits events --examples <directory>
                           write an example script of every event (with everything it gets
                           documented at its top) into the directory

  GITS_START=<script>      not an event of a command: the script runs once, as the first thing
                           of a command which has events (before its event START). gits waits
                           for it, a failure stops the command. $1 START, $2 command

  GITS_EXIT=<script>       not an event of a command: the script runs as the last thing of
                           every start of gits (also after an error, Ctrl+C, kill; not kill -9),
                           like "trap ... EXIT" of a shell. $1 EXIT, $2 command, $3 exit code

Environment variables:

"#
    );
    out.push_str(&env_table());
    if env_any(ENV_SOURCE).is_none() {
        out.push('\n');
        out.push_str(&red(&format!(
            "  {ENV_SOURCE} is not defined: only --help, --version and --update work without it.\n  Add to ~/.zshrc or ~/.bashrc:\n\n    export {ENV_SOURCE}=\"git@github.com:<owner>/<storage repository>.git\"\n"
        )));
    }
    out
}

// the command itself, between the events START and END
fn dispatch(
    command: &str,
    rest: &[String],
    yes: bool,
    encrypt: bool,
    cwd: PathBuf,
) -> Result<i32, String> {
    events::start(command, &cwd)?;
    events::fire("START", &[], &[])?;

    if command == "update" {
        return update::run(rest);
    }

    // checked before anything else: nothing (besides help, version, events and update) works without the storage
    let Some(source) = env_any(ENV_SOURCE) else {
        return Err(format!(
            "env var {ENV_SOURCE} is not defined or empty, it has to point to the storage repository, e.g.:\n\n  export {ENV_SOURCE}=\"git@github.com:<owner>/<storage repository>.git\"\n\nsee: gits --help"
        ));
    };

    let ctx = Ctx {
        cwd,
        source,
        socket: env_any(socket::ENV_SOCKET),
        template: env_any(commands::ENV_TEMPLATE),
    };

    match command {
        "state" => ops::state(&ctx),
        "find" => commands::find(&ctx),
        "diff" => ops::diff(&ctx),
        "isinsync" => ops::isinsync(&ctx),
        "push" => ops::push(&ctx, yes),
        "pull" => ops::pull(&ctx, yes),
        "url" => ops::url(&ctx),
        "crypt" => crypt::run(&ctx, rest, yes),
        "init" => commands::init(&ctx),
        "add" => commands::add(&ctx, rest, encrypt, yes),
        "move" => commands::mv(&ctx, rest),
        "migrate" => commands::migrate(&ctx, rest),
        other => Err(format!("unknown command >{other}<, see: gits --help")),
    }
}

fn run() -> i32 {
    let args: Vec<String> = std::env::args().skip(1).collect();

    let first = args.first().map(|s| s.as_str()).unwrap_or("--help");

    match first {
        "--help" | "-h" | "help" => {
            println!("{}", help());
            return 0;
        }
        "--version" => {
            println!("gits {VERSION}");
            return 0;
        }
        "events" => {
            return match events::run(&args[1..]) {
                Ok(code) => code,
                Err(e) => {
                    eprintln!("{}", red(&format!("gits error: {e}")));
                    1
                }
            };
        }
        "list" => {
            let result = std::env::current_dir()
                .map_err(|e| format!("can't read current directory: {e}"))
                .and_then(|cwd| commands::list(&cwd, &args[1..]));
            return match result {
                Ok(code) => code,
                Err(e) => {
                    eprintln!("{}", red(&format!("gits error: {e}")));
                    1
                }
            };
        }
        _ => {}
    }

    let mut yes = false;
    let mut encrypt = false;
    let mut positional: Vec<String> = Vec::new();
    // --update has arguments of its own (--check, a tag)
    let is_update = first == "--update";
    if is_update {
        positional.push("update".to_string());
        positional.extend(args[1..].iter().cloned());
    } else {
        for arg in &args {
            match arg.as_str() {
                "--yes" => yes = true,
                "-e" | "--encrypt" => encrypt = true,
                // gits crypt has flags of its own
                "--storage" | "--rewrap-only" if first == "crypt" => positional.push(arg.clone()),
                flag if flag.starts_with('-') && flag.len() > 1 => {
                    eprintln!(
                        "{}",
                        red(&format!(
                            "gits error: unsupported flag {flag}, see: gits --help"
                        ))
                    );
                    return 1;
                }
                _ => positional.push(arg.clone()),
            }
        }
    }
    let command = positional.first().cloned().unwrap_or_default();
    let rest = &positional[1.min(positional.len())..];

    let cwd = match std::env::current_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!(
                "{}",
                red(&format!("gits error: can't read current directory: {e}"))
            );
            return 1;
        }
    };

    events::init(&command, &cwd, &args);

    let code = match dispatch(&command, rest, yes, encrypt, cwd) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("{}", red(&format!("gits error: {e}")));
            events::fire_quietly(
                "ERROR",
                std::slice::from_ref(&e),
                &[("GITS_EVENT_ERROR", e.clone())],
            );
            // isinsync: 1 means "not in sync", an error must not look like it
            if command == "isinsync" {
                2
            } else {
                1
            }
        }
    };

    // everything temporary is removed by now (also after Ctrl+C: then the exit code is 130)
    let code = if util::interrupted() { 130 } else { code };
    events::fire_quietly(
        "END",
        &[code.to_string()],
        &[("GITS_EVENT_EXIT_CODE", code.to_string())],
    );
    code
}

fn main() {
    util::install_signal_handlers();
    // run() has returned: everything temporary is already removed
    let code = run();
    // like "trap ... EXIT": whatever was started and however it ended
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = match args.first().map(|s| s.as_str()) {
        Some("--update") => "update".to_string(),
        _ => args
            .iter()
            .find(|a| !a.starts_with('-'))
            .cloned()
            .unwrap_or_default(),
    };
    if let Ok(cwd) = std::env::current_dir() {
        let code = if util::interrupted() { 130 } else { code };
        events::exit(&command, &cwd, code);
    }
    if util::interrupted() {
        eprintln!("{}", yellow("gits: interrupted"));
        std::process::exit(130);
    }
    std::process::exit(code);
}
