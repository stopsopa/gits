mod cli;
mod commands;
mod config;
mod ops;
mod socket;
mod update;
mod util;

use std::path::PathBuf;

use util::{env, red, yellow};

// the pushed tag for a release, "dev" for every other build (build.rs)
pub const VERSION: &str = env!("GITS_BUILD_VERSION");

pub const ENV_SOURCE: &str = "GITSTORAGESOURCE";

// what every command needs
pub struct Ctx {
    // directory gits was started in
    pub cwd: PathBuf,
    // GITSTORAGESOURCE: the storage repository
    pub source: String,
    // GITSTORAGETENCRYPTIONSOCKET
    pub socket: Option<String>,
    // GITSTORAGETEMPLATE
    pub template: Option<String>,
}

struct Var {
    name: &'static str,
    default: &'static str,
    required: bool,
    about: &'static str,
}

const VARS: [Var; 6] = [
    Var {
        name: ENV_SOURCE,
        default: "",
        required: true,
        about: "the storage: git repository where files are kept, e.g. git@github.com:stopsopa/gitstorage.git",
    },
    Var {
        name: config::ENV_SHELL,
        default: config::DEFAULT_SHELL,
        required: false,
        about: "shell which executes .git/gits.sh (the config is a shell script)",
    },
    Var {
        name: socket::ENV_SOCKET,
        default: "",
        required: false,
        about: "unix socket of the encoder process, needed only for elements SOURCE:e:TARGET",
    },
    Var {
        name: commands::ENV_TEMPLATE,
        default: "",
        required: false,
        about: "url or file: template of .git/gits.sh for 'gits init' (default: built-in)",
    },
    Var {
        name: update::ENV_RELEASES,
        default: update::RELEASES,
        required: false,
        about: "where 'gits --update' takes releases from (url or directory)",
    },
    Var {
        name: update::ENV_CONFIRM,
        default: "true",
        required: false,
        about: "false: 'gits --update' doesn't ask before replacing the binary",
    },
];

fn pad(text: &str, width: usize) -> String {
    format!(
        "{text}{}",
        " ".repeat(width.saturating_sub(text.chars().count()))
    )
}

// name | value found in the environment | default | the value which wins
fn env_table() -> String {
    let rows: Vec<[String; 4]> = VARS
        .iter()
        .map(|v| {
            let found = env(v.name);
            let used = match (&found, v.default.is_empty()) {
                (Some(value), _) => value.clone(),
                (None, false) => v.default.to_string(),
                (None, true) if v.required => "MISSING (required)".to_string(),
                (None, true) => "(not used)".to_string(),
            };
            [
                v.name.to_string(),
                found.unwrap_or_else(|| "(not defined)".to_string()),
                if v.default.is_empty() {
                    "(none)".to_string()
                } else {
                    v.default.to_string()
                },
                used,
            ]
        })
        .collect();

    let header = ["variable", "found in env", "default", "used"];
    let mut widths = header.map(|h| h.len());
    for row in &rows {
        for (i, cell) in row.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }

    let line = |cells: [&str; 4]| -> String {
        let padded: Vec<String> = cells
            .iter()
            .enumerate()
            .map(|(i, c)| pad(c, widths[i]))
            .collect();
        format!("  {}", padded.join(" | ").trim_end())
    };

    let mut out = String::new();
    out.push_str(&line(header));
    out.push('\n');
    let separator: Vec<String> = widths.iter().map(|w| "-".repeat(*w)).collect();
    out.push_str(&format!("  {}\n", separator.join("-|-")));
    for (row, var) in rows.iter().zip(VARS.iter()) {
        let text = line([&row[0], &row[1], &row[2], &row[3]]);
        if var.required && env(var.name).is_none() {
            out.push_str(&red(&text));
        } else {
            out.push_str(&text);
        }
        out.push('\n');
    }
    out.push('\n');
    for var in VARS.iter() {
        out.push_str(&format!("  {}  {}\n", pad(var.name, widths[0]), var.about));
    }
    out
}

fn help() -> String {
    let mut out = format!(
        r#"
gits {VERSION}

Keeps files which don't belong to the repository of a project (.env, local configs, dotfiles)
in one private git repository, the storage. Each project describes its files in .git/gits.sh:

    GITSTORAGETARGETDIR="git@github.com:owner__repo.git"     # directory of the project in the storage
    GITSTORAGELIST=(
        "gits.sh::$GITSTORAGETARGETDIR/gits.sh"              # "SOURCE::TARGET"    stored as it is
        "../.env:e:$GITSTORAGETARGETDIR/.env"                # "SOURCE:e:TARGET"   stored encrypted
        "~/.zshrc::$GITSTORAGETARGETDIR/.zshrc"
    )

    SOURCE  file on this machine: absolute, starting with ~/, or relative to .git
    TARGET  path in the storage

In any directory:

  gits state            find all projects below the current directory (.git/gits.sh, .git/gitstorage-config.sh)
                        and say for each whether its files are in sync with the storage.
                        Prints 'cd "<project>"' + 'gits diff' for each, ready to paste.
  gits find             only list the directories of those projects, one per line
  gits migrate all      .git/gitstorage-config.sh -> .git/gits.sh in all projects below the current directory

In the root of a project (the directory with .git):

  gits init             create .git/gits.sh: from the storage when it has one for this project,
                        else from the template
  gits diff             what differs between local files and the storage (git diff). Exit code 1 when not in sync
  gits isinsync         the same check, only the exit code: 0 in sync, 1 not in sync, 2 error
  gits push --yes       local files -> storage (commit and push). Without --yes nothing is changed
  gits pull --yes       storage -> local files (they are overwritten). Without --yes nothing is changed
  gits url              web address of the directory of this project in the storage
  gits add [-e] <file|directory> ...
                        register files in .git/gits.sh (only the config is changed). -e: as encrypted
  gits move <old remote> <new remote>
                        print the procedure of renaming the directory in the storage after
                        the remote 'origin' of the project changed
  gits migrate          .git/gitstorage-config.sh -> .git/gits.sh (also done automatically when needed)

Everything which needs the storage clones it to a directory with a random name in the current
directory and removes it at the end.

The tool itself:

  gits --help
  gits --version
  gits --update            update to the latest release
  gits --update <tag>      install the given release (also an older one), e.g. v0.1.0
  gits --update --check    only say whether there is something newer, change nothing

Environment variables:

"#
    );
    out.push_str(&env_table());
    if env(ENV_SOURCE).is_none() {
        out.push('\n');
        out.push_str(&red(&format!(
            "  {ENV_SOURCE} is not defined: only --help, --version and --update work without it.\n  Add to ~/.zshrc or ~/.bashrc:\n\n    export {ENV_SOURCE}=\"git@github.com:<owner>/<storage repository>.git\"\n"
        )));
    }
    out
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
        "--update" => {
            return match update::run(&args[1..]) {
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
    for arg in &args {
        match arg.as_str() {
            "--yes" => yes = true,
            "-e" | "--encrypt" => encrypt = true,
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
    let command = positional.first().cloned().unwrap_or_default();
    let rest = &positional[1.min(positional.len())..];

    // checked before anything else: nothing (besides help, version and update) works without the storage
    let Some(source) = env(ENV_SOURCE) else {
        eprintln!(
            "{}",
            red(&format!(
                "gits error: env var {ENV_SOURCE} is not defined or empty, it has to point to the storage repository, e.g.:\n\n  export {ENV_SOURCE}=\"git@github.com:<owner>/<storage repository>.git\"\n\nsee: gits --help"
            ))
        );
        return 1;
    };

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

    let ctx = Ctx {
        cwd,
        source,
        socket: env(socket::ENV_SOCKET),
        template: env(commands::ENV_TEMPLATE),
    };

    let result = match command.as_str() {
        "state" => ops::state(&ctx),
        "find" => commands::find(&ctx),
        "diff" => ops::diff(&ctx),
        "isinsync" => ops::isinsync(&ctx),
        "push" => ops::push(&ctx, yes),
        "pull" => ops::pull(&ctx, yes),
        "url" => ops::url(&ctx),
        "init" => commands::init(&ctx),
        "add" => commands::add(&ctx, rest, encrypt),
        "move" => commands::mv(&ctx, rest),
        "migrate" => commands::migrate(&ctx, rest),
        other => Err(format!("unknown command >{other}<, see: gits --help")),
    };

    match result {
        Ok(code) => code,
        Err(e) => {
            eprintln!("{}", red(&format!("gits error: {e}")));
            // isinsync: 1 means "not in sync", an error must not look like it
            if command == "isinsync" {
                2
            } else {
                1
            }
        }
    }
}

fn main() {
    util::install_signal_handlers();
    // run() has returned: everything temporary is already removed
    let code = run();
    if util::interrupted() {
        eprintln!("{}", yellow("gits: interrupted"));
        std::process::exit(130);
    }
    std::process::exit(code);
}
