use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::cli::{cli, Options};
use crate::config;
use crate::util::{env, env_any, expand_tilde, red, yellow};

/*
 * Lifecycle events: between the stages of every command gits runs the scripts the user
 * registered for them. Everything about them for a user is in LIFECYCLE.md, in short:
 *
 *   GITS_<COMMAND>_<EVENT>=/path/to/script     script of one event of one command
 *   GITS_<COMMAND>_ALL=/path/to/script         script of every event of one command
 *   GITS_ALL=/path/to/script                   script of every event of every command
 *
 * - the value is a path to a script ("~/" allowed), executed by the shell from GITS_SHELL:
 *     $GITS_SHELL <script> <EVENT> <command> [arguments of the event]
 * - the variables are read from the environment and, once the config of a project was executed,
 *   also from .git/gits.sh (a project can carry its own scripts)
 * - the script gets everything gits knows at that moment as GITS_EVENT_* env vars
 * - START and BEFORE_* scripts can stop the command with a non-zero exit code, a failure of any
 *   other script is only reported
 * - "replaceable" events (FIND) are different: their script does a part of the work of gits and
 *   gits reads its stdout. Without a script of the user the default from events/defaults/ runs
 * - gits started from inside of a script runs no scripts at all (GITS_EVENT_RUNNING): no recursion
 *
 * The list of events (REGISTRY) is the single source for "gits events", for the example scripts
 * in events/examples/ and for the reference tables of LIFECYCLE.md.
 */
pub const ENV_RUNNING: &str = "GITS_EVENT_RUNNING";

pub const DEFAULT_FIND: &str = include_str!("../events/defaults/FIND.sh");

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    // the script is told that something happened / is about to happen
    Notify,
    // the script does the work and gits reads its stdout
    Replace,
}

pub struct Def {
    pub name: &'static str,
    pub kind: Kind,
    // one line: the moment the event is fired
    pub when: &'static str,
    // how many times in one run
    pub fired: &'static str,
    // arguments after <EVENT> <command>
    pub args: &'static [&'static str],
    // env vars which exist only for this event: (name, meaning)
    pub vars: &'static [(&'static str, &'static str)],
}

const FILE_VARS: &[(&str, &str)] = &[
    ("GITS_EVENT_FILE_SOURCE", "the local file, absolute path"),
    (
        "GITS_EVENT_FILE_SOURCE_RAW",
        "SOURCE as it is written in the config",
    ),
    (
        "GITS_EVENT_FILE_TARGET",
        "TARGET: path of the file in the storage",
    ),
    (
        "GITS_EVENT_FILE_STORED",
        "the file in the temporary clone, absolute path",
    ),
    (
        "GITS_EVENT_FILE_ENCRYPTED",
        "1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET",
    ),
    (
        "GITS_EVENT_FILE_INDEX",
        "position of the element in GITS_LIST, from 1",
    ),
];

const FILE_ARGS: &[&str] = &["local file (absolute)", "file in the temporary clone"];

const START: Def = Def {
    name: "START",
    kind: Kind::Notify,
    when: "the arguments are read, nothing else happened yet",
    fired: "once",
    args: &[],
    vars: &[],
};
const END: Def = Def {
    name: "END",
    kind: Kind::Notify,
    when: "the last thing before gits exits, always: also after an error and after Ctrl+C",
    fired: "once",
    args: &["exit code"],
    vars: &[(
        "GITS_EVENT_EXIT_CODE",
        "the exit code gits ends with (130 after Ctrl+C)",
    )],
};
const ERROR: Def = Def {
    name: "ERROR",
    kind: Kind::Notify,
    when: "the command failed, its error message was just printed",
    fired: "once, only when the command fails",
    args: &["error message"],
    vars: &[("GITS_EVENT_ERROR", "the error message")],
};
const CONFIG_LOADED: Def = Def {
    name: "CONFIG_LOADED",
    kind: Kind::Notify,
    when: ".git/gits.sh was executed: GITS_TARGETDIR and the list are known. \
           From here on the scripts defined in the config run too",
    fired: "once (state: once per project)",
    args: &[],
    vars: &[],
};
const BEFORE_CLONE: Def = Def {
    name: "BEFORE_CLONE",
    kind: Kind::Notify,
    when: "the temporary directory exists and is empty, 'git clone' of the storage is next",
    fired: "once",
    args: &["temporary directory"],
    vars: &[],
};
const AFTER_CLONE: Def = Def {
    name: "AFTER_CLONE",
    kind: Kind::Notify,
    when: "the storage is cloned into the temporary directory",
    fired: "once",
    args: &["temporary directory"],
    vars: &[],
};
const BEFORE_DECRYPT: Def = Def {
    name: "BEFORE_DECRYPT",
    kind: Kind::Notify,
    when: "one stored file of an element SOURCE:e:TARGET is about to be decrypted",
    fired: "once per encrypted element whose file is in the storage",
    args: FILE_ARGS,
    vars: FILE_VARS,
};
const AFTER_DECRYPT: Def = Def {
    name: "AFTER_DECRYPT",
    kind: Kind::Notify,
    when: "that file was decrypted (or turned out to be stored not encrypted)",
    fired: "once per encrypted element whose file is in the storage",
    args: FILE_ARGS,
    vars: FILE_VARS,
};
const BEFORE_COPY: Def = Def {
    name: "BEFORE_COPY",
    kind: Kind::Notify,
    when: "one file is about to be copied: local file -> clone (pull --yes: clone -> local file)",
    fired: "once per element of the list",
    args: FILE_ARGS,
    vars: FILE_VARS,
};
const AFTER_COPY: Def = Def {
    name: "AFTER_COPY",
    kind: Kind::Notify,
    when: "that file was copied",
    fired: "once per element of the list",
    args: FILE_ARGS,
    vars: FILE_VARS,
};
const BEFORE_COMPARE: Def = Def {
    name: "BEFORE_COMPARE",
    kind: Kind::Notify,
    when: "all local files are in the clone, 'git status' which decides \"in sync or not\" is next",
    fired: "once (state: once per project)",
    args: &[],
    vars: &[],
};
const AFTER_COMPARE: Def = Def {
    name: "AFTER_COMPARE",
    kind: Kind::Notify,
    when: "it is known whether the local files and the storage are in sync",
    fired: "once (state: once per project)",
    args: &["result"],
    vars: &[
        (
            "GITS_EVENT_RESULT",
            "insync, differs, or missing (a local file of the list doesn't exist)",
        ),
        (
            "GITS_EVENT_CHANGED",
            "local files which differ from the storage, absolute paths, one per line",
        ),
    ],
};
const BEFORE_ENCRYPT: Def = Def {
    name: "BEFORE_ENCRYPT",
    kind: Kind::Notify,
    when: "push --yes: the plain copy of one file lies next to its stored file, encryption is next",
    fired: "once per encrypted element whose content changed",
    args: FILE_ARGS,
    vars: &[
        ("GITS_EVENT_FILE_SOURCE", "the local file, absolute path"),
        (
            "GITS_EVENT_FILE_SOURCE_RAW",
            "SOURCE as it is written in the config",
        ),
        (
            "GITS_EVENT_FILE_TARGET",
            "TARGET: path of the file in the storage",
        ),
        (
            "GITS_EVENT_FILE_STORED",
            "the file in the temporary clone, absolute path",
        ),
        ("GITS_EVENT_FILE_ENCRYPTED", "1"),
        (
            "GITS_EVENT_FILE_INDEX",
            "position of the element in GITS_LIST, from 1",
        ),
        (
            "GITS_EVENT_FILE_PLAIN",
            "the temporary plain copy (TARGET.hash...), removed right after the encryption",
        ),
    ],
};
const AFTER_ENCRYPT: Def = Def {
    name: "AFTER_ENCRYPT",
    kind: Kind::Notify,
    when: "push --yes: that file was encrypted over its stored file, the plain copy is removed",
    fired: "once per encrypted element whose content changed",
    args: FILE_ARGS,
    vars: FILE_VARS,
};
const BEFORE_COMMIT: Def = Def {
    name: "BEFORE_COMMIT",
    kind: Kind::Notify,
    when:
        "push --yes: the clone holds what is going to be stored, 'git add' + 'git commit' are next",
    fired: "once, only when there is something to store",
    args: &[],
    vars: &[],
};
const AFTER_COMMIT: Def = Def {
    name: "AFTER_COMMIT",
    kind: Kind::Notify,
    when: "push --yes: the commit exists in the clone, it is not in the storage yet",
    fired: "once, only when there is something to store",
    args: &["commit hash"],
    vars: &[("GITS_EVENT_COMMIT", "hash of the new commit")],
};
const BEFORE_PUSH: Def = Def {
    name: "BEFORE_PUSH",
    kind: Kind::Notify,
    when: "push --yes: 'git push' to the storage is next. The last moment to stop it",
    fired: "once, only when there is something to store",
    args: &["commit hash"],
    vars: &[("GITS_EVENT_COMMIT", "hash of the new commit")],
};
const AFTER_PUSH: Def = Def {
    name: "AFTER_PUSH",
    kind: Kind::Notify,
    when: "push --yes: the storage has the new commit",
    fired: "once, only when there is something to store",
    args: &["commit hash"],
    vars: &[("GITS_EVENT_COMMIT", "hash of the new commit")],
};
const BEFORE_CLEANUP: Def = Def {
    name: "BEFORE_CLEANUP",
    kind: Kind::Notify,
    when: "the temporary directory is about to be removed: the last moment to look into it",
    fired: "once",
    args: &["temporary directory"],
    vars: &[],
};
const AFTER_CLEANUP: Def = Def {
    name: "AFTER_CLEANUP",
    kind: Kind::Notify,
    when: "the temporary directory is removed",
    fired: "once",
    args: &["temporary directory"],
    vars: &[],
};
const FIND: Def = Def {
    name: "FIND",
    kind: Kind::Replace,
    when:
        "the projects below the current directory have to be found. The script does it: it prints \
           the path of every config (.git/gits.sh, .git/gitstorage-config.sh), one per line. \
           Default: events/defaults/FIND.sh",
    fired: "once",
    args: &["directory to search"],
    vars: &[],
};
const FOUND: Def = Def {
    name: "FOUND",
    kind: Kind::Notify,
    when: "the projects are found",
    fired: "once",
    args: &["number of projects"],
    vars: &[
        ("GITS_EVENT_FOUND_COUNT", "number of projects"),
        (
            "GITS_EVENT_FOUND",
            "directories of the projects, relative to GITS_EVENT_PWD, one per line",
        ),
    ],
};
const BEFORE_PROJECT: Def = Def {
    name: "BEFORE_PROJECT",
    kind: Kind::Notify,
    when: "state: one project is about to be checked",
    fired: "once per project",
    args: &[
        "directory of the project",
        "number of the project",
        "number of projects",
    ],
    vars: &[
        ("GITS_EVENT_STATE_INDEX", "number of the project, from 1"),
        ("GITS_EVENT_STATE_COUNT", "number of projects"),
    ],
};
const AFTER_PROJECT: Def = Def {
    name: "AFTER_PROJECT",
    kind: Kind::Notify,
    when: "state: that project was checked",
    fired: "once per project",
    args: &["directory of the project", "result"],
    vars: &[
        ("GITS_EVENT_STATE_INDEX", "number of the project, from 1"),
        ("GITS_EVENT_STATE_COUNT", "number of projects"),
        (
            "GITS_EVENT_RESULT",
            "insync, differs, missing, or error (the project could not be checked)",
        ),
        (
            "GITS_EVENT_COUNT_SUCCESS",
            "projects in sync so far, this one included",
        ),
        (
            "GITS_EVENT_COUNT_ERROR",
            "projects not in sync or failed so far, this one included",
        ),
    ],
};
const BEFORE_WRITE: Def = Def {
    name: "BEFORE_WRITE",
    kind: Kind::Notify,
    when: ".git/gits.sh is about to be written",
    fired: "once, only when there is something to write",
    args: &["path of the config"],
    vars: &[(
        "GITS_EVENT_WRITE_ORIGIN",
        "init: storage, template or built-in. add: number of lines which are added",
    )],
};
const AFTER_WRITE: Def = Def {
    name: "AFTER_WRITE",
    kind: Kind::Notify,
    when: ".git/gits.sh was written",
    fired: "once, only when there is something to write",
    args: &["path of the config"],
    vars: &[(
        "GITS_EVENT_WRITE_ORIGIN",
        "init: storage, template or built-in. add: number of lines which were added",
    )],
};
const BEFORE_RENAME: Def = Def {
    name: "BEFORE_RENAME",
    kind: Kind::Notify,
    when: "migrate: .git/gitstorage-config.sh of one project is about to become .git/gits.sh",
    fired: "once per project which is migrated",
    args: &["old config", "new config"],
    vars: &[
        ("GITS_EVENT_RENAME_FROM", "the old config, absolute path"),
        ("GITS_EVENT_RENAME_TO", "the new config, absolute path"),
    ],
};
const AFTER_RENAME: Def = Def {
    name: "AFTER_RENAME",
    kind: Kind::Notify,
    when: "migrate: the new config is written, the old one is removed",
    fired: "once per project which is migrated",
    args: &["old config", "new config"],
    vars: &[
        ("GITS_EVENT_RENAME_FROM", "the old config, absolute path"),
        ("GITS_EVENT_RENAME_TO", "the new config, absolute path"),
    ],
};
const BEFORE_DOWNLOAD: Def = Def {
    name: "BEFORE_DOWNLOAD",
    kind: Kind::Notify,
    when: "--update: the release to install is known, the download is next",
    fired: "once, only when there is something to install",
    args: &["tag of the release"],
    vars: &[
        (
            "GITS_EVENT_UPDATE_TAG",
            "tag of the release which is installed",
        ),
        ("GITS_EVENT_UPDATE_INSTALLED", "the file which is replaced"),
    ],
};
const AFTER_DOWNLOAD: Def = Def {
    name: "AFTER_DOWNLOAD",
    kind: Kind::Notify,
    when: "--update: the new binary is downloaded next to the installed one, checked and tested",
    fired: "once, only when there is something to install",
    args: &["tag of the release"],
    vars: &[
        (
            "GITS_EVENT_UPDATE_TAG",
            "tag of the release which is installed",
        ),
        ("GITS_EVENT_UPDATE_INSTALLED", "the file which is replaced"),
    ],
};
const BEFORE_REPLACE: Def = Def {
    name: "BEFORE_REPLACE",
    kind: Kind::Notify,
    when: "--update: the installed binary is about to be replaced",
    fired: "once, only when there is something to install",
    args: &["tag of the release"],
    vars: &[
        (
            "GITS_EVENT_UPDATE_TAG",
            "tag of the release which is installed",
        ),
        ("GITS_EVENT_UPDATE_INSTALLED", "the file which is replaced"),
    ],
};
const AFTER_REPLACE: Def = Def {
    name: "AFTER_REPLACE",
    kind: Kind::Notify,
    when: "--update: the installed binary is the new one and it works",
    fired: "once, only when there is something to install",
    args: &["tag of the release"],
    vars: &[
        (
            "GITS_EVENT_UPDATE_TAG",
            "tag of the release which is installed",
        ),
        ("GITS_EVENT_UPDATE_INSTALLED", "the file which is replaced"),
    ],
};

// events of every command, in the order they happen
pub const REGISTRY: &[(&str, &[Def])] = &[
    (
        "state",
        &[
            START,
            FIND,
            FOUND,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_PROJECT,
            CONFIG_LOADED,
            BEFORE_DECRYPT,
            AFTER_DECRYPT,
            BEFORE_COPY,
            AFTER_COPY,
            BEFORE_COMPARE,
            AFTER_COMPARE,
            AFTER_PROJECT,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    ("find", &[START, FIND, FOUND, ERROR, END]),
    (
        "init",
        &[
            START,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_WRITE,
            AFTER_WRITE,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    ("add", &[START, BEFORE_WRITE, AFTER_WRITE, ERROR, END]),
    (
        "diff",
        &[
            START,
            CONFIG_LOADED,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_DECRYPT,
            AFTER_DECRYPT,
            BEFORE_COPY,
            AFTER_COPY,
            BEFORE_COMPARE,
            AFTER_COMPARE,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    (
        "isinsync",
        &[
            START,
            CONFIG_LOADED,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_DECRYPT,
            AFTER_DECRYPT,
            BEFORE_COPY,
            AFTER_COPY,
            BEFORE_COMPARE,
            AFTER_COMPARE,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    (
        "push",
        &[
            START,
            CONFIG_LOADED,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_DECRYPT,
            AFTER_DECRYPT,
            BEFORE_COPY,
            AFTER_COPY,
            BEFORE_COMPARE,
            AFTER_COMPARE,
            BEFORE_ENCRYPT,
            AFTER_ENCRYPT,
            BEFORE_COMMIT,
            AFTER_COMMIT,
            BEFORE_PUSH,
            AFTER_PUSH,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    (
        "pull",
        &[
            START,
            CONFIG_LOADED,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_DECRYPT,
            AFTER_DECRYPT,
            BEFORE_COPY,
            AFTER_COPY,
            BEFORE_COMPARE,
            AFTER_COMPARE,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    ("url", &[START, CONFIG_LOADED, ERROR, END]),
    (
        "crypt",
        &[
            START,
            FIND,
            FOUND,
            CONFIG_LOADED,
            BEFORE_CLONE,
            AFTER_CLONE,
            BEFORE_COMMIT,
            AFTER_COMMIT,
            BEFORE_PUSH,
            AFTER_PUSH,
            BEFORE_CLEANUP,
            AFTER_CLEANUP,
            ERROR,
            END,
        ],
    ),
    ("move", &[START, ERROR, END]),
    (
        "migrate",
        &[START, FIND, FOUND, BEFORE_RENAME, AFTER_RENAME, ERROR, END],
    ),
    (
        "update",
        &[
            START,
            BEFORE_DOWNLOAD,
            AFTER_DOWNLOAD,
            BEFORE_REPLACE,
            AFTER_REPLACE,
            ERROR,
            END,
        ],
    ),
];

// env vars every script gets: (name, meaning)
pub const ALWAYS: &[(&str, &str)] = &[
    (
        "GITS_EVENT",
        "name of the variable of this event, e.g. GITS_PUSH_BEFORE_ENCRYPT (also when the script runs as *_ALL)",
    ),
    ("GITS_EVENT_NAME", "the event, e.g. BEFORE_ENCRYPT"),
    ("GITS_EVENT_COMMAND", "the command, e.g. push"),
    (
        "GITS_EVENT_SEQ",
        "number of this event among all events of this run, from 1 (events without a script count too)",
    ),
    (
        "GITS_EVENT_INDEX",
        "which occurrence of this event it is in this run, from 1 (BEFORE_COPY of the 3rd file: 3)",
    ),
    (
        "GITS_EVENT_TRIGGER",
        "the variable which pointed to this script: the one of the event, GITS_<COMMAND>_ALL or GITS_ALL",
    ),
    (
        "GITS_EVENT_TRIGGER_FROM",
        "where that variable was defined: env or config (.git/gits.sh)",
    ),
    ("GITS_EVENT_SCRIPT", "path of this script"),
    (
        "GITS_EVENT_CAN_STOP",
        "1: a non-zero exit code of this script stops the command (START, BEFORE_*). 0: it is only reported",
    ),
    (
        "GITS_EVENT_RUNNING",
        "1. gits started from inside of a script sees it and runs no scripts itself",
    ),
    ("GITS_EVENT_PWD", "directory where gits was called"),
    (
        "GITS_EVENT_ARGS",
        "arguments gits was called with, separated by spaces",
    ),
    ("GITS_EVENT_BIN", "path of the gits binary"),
    ("GITS_EVENT_VERSION", "version of gits"),
    ("GITS_EVENT_PID", "process id of gits"),
    ("GITS_SOURCE", "the storage, as gits uses it"),
    ("GITS_SHELL", "the shell which runs the config and the scripts"),
    (
        "GITS_ENCRYPTION_SOCKET",
        "socket of the encoder process (empty when not defined)",
    ),
    (
        "GITS_TEMPLATE",
        "template of 'gits init' (empty when not defined)",
    ),
];

// env vars which appear as soon as gits knows them and stay till the end: (name, meaning)
pub const ONCE_KNOWN: &[(&str, &str)] = &[
    (
        "GITS_EVENT_PROJECT_DIR",
        "root of the project (state: of the project which is checked right now)",
    ),
    ("GITS_EVENT_CONFIG", "path of .git/gits.sh of the project"),
    (
        "GITS_TARGETDIR",
        "directory of the project in the storage, from the config",
    ),
    (
        "GITS_EVENT_LIST_COUNT",
        "number of elements of GITS_LIST",
    ),
    (
        "GITS_EVENT_LIST",
        "all elements, one per line: <e|p><TAB>local file (absolute)<TAB>TARGET   (e: encrypted, p: plain)",
    ),
    (
        "GITS_EVENT_TEMP_DIR",
        "the temporary directory: the clone of the storage",
    ),
    (
        "GITS_EVENT_STORAGE_DIR",
        "directory of the project inside of the clone: <temporary directory>/<GITS_TARGETDIR>",
    ),
    ("GITS_EVENT_STORAGE_BRANCH", "branch of the storage"),
    ("GITS_EVENT_YES", "1 when --yes was given, else 0"),
];

struct State {
    // lower case: "push"
    command: String,
    pwd: PathBuf,
    context: BTreeMap<String, String>,
    seq: u32,
    counts: HashMap<String, u32>,
    // GITS_<COMMAND>_<EVENT> / *_ALL variables defined by the config of the project
    from_config: HashMap<String, String>,
    // gits itself was started by a script
    nested: bool,
    // isinsync: stdout belongs to nobody, what a script prints goes to stderr
    stdout_to_stderr: bool,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

fn defs(command: &str) -> &'static [Def] {
    REGISTRY
        .iter()
        .find(|(name, _)| *name == command)
        .map(|(_, defs)| *defs)
        .unwrap_or(&[])
}

pub fn variable(command: &str, event: &str) -> String {
    format!("GITS_{}_{}", command.to_uppercase(), event)
}

fn can_stop(event: &str) -> bool {
    event == "START" || event.starts_with("BEFORE_")
}

// called once, before the first event
pub fn init(command: &str, pwd: &Path, args: &[String]) {
    let mut context = BTreeMap::new();
    context.insert("GITS_EVENT_PWD".to_string(), pwd.display().to_string());
    context.insert("GITS_EVENT_ARGS".to_string(), args.join(" "));
    context.insert(
        "GITS_EVENT_BIN".to_string(),
        std::env::current_exe()
            .map(|p| p.display().to_string())
            .unwrap_or_default(),
    );
    context.insert("GITS_EVENT_VERSION".to_string(), crate::VERSION.to_string());
    context.insert("GITS_EVENT_PID".to_string(), std::process::id().to_string());
    context.insert(
        "GITS_SOURCE".to_string(),
        env_any(crate::ENV_SOURCE).unwrap_or_default(),
    );
    context.insert("GITS_SHELL".to_string(), config::shell());
    context.insert(
        "GITS_ENCRYPTION_SOCKET".to_string(),
        env_any(crate::socket::ENV_SOCKET).unwrap_or_default(),
    );
    context.insert(
        "GITS_TEMPLATE".to_string(),
        env_any(crate::commands::ENV_TEMPLATE).unwrap_or_default(),
    );
    context.insert(
        "GITS_EVENT_YES".to_string(),
        if args.iter().any(|a| a == "--yes") {
            "1"
        } else {
            "0"
        }
        .to_string(),
    );

    *STATE.lock().unwrap() = Some(State {
        command: command.to_string(),
        pwd: pwd.to_path_buf(),
        context,
        seq: 0,
        counts: HashMap::new(),
        from_config: HashMap::new(),
        nested: env(ENV_RUNNING).is_some(),
        stdout_to_stderr: command == "isinsync",
    });
}

// a value which stays for all following events
pub fn set(name: &str, value: impl Into<String>) {
    if let Some(state) = STATE.lock().unwrap().as_mut() {
        state.context.insert(name.to_string(), value.into());
    }
}

pub fn unset(name: &str) {
    if let Some(state) = STATE.lock().unwrap().as_mut() {
        state.context.remove(name);
    }
}

// names of the variables the config of a project may define for the running command
pub fn names_for_config() -> Vec<String> {
    let guard = STATE.lock().unwrap();
    let Some(state) = guard.as_ref() else {
        return Vec::new();
    };
    if state.nested {
        return Vec::new();
    }
    let mut names: Vec<String> = defs(&state.command)
        .iter()
        .filter(|d| d.kind == Kind::Notify)
        .map(|d| variable(&state.command, d.name))
        .collect();
    names.push(variable(&state.command, "ALL"));
    names.push("GITS_ALL".to_string());
    names
}

// what the config of the project defined (state: replaced with every project)
pub fn set_config_scripts(scripts: HashMap<String, String>) {
    if let Some(state) = STATE.lock().unwrap().as_mut() {
        state.from_config = scripts;
    }
}

struct Call {
    trigger: String,
    from: &'static str,
    script: String,
}

struct Prepared {
    shell: String,
    pwd: PathBuf,
    vars: Vec<(String, String)>,
    calls: Vec<Call>,
    stdout_to_stderr: bool,
    command: String,
}

// counts the event and collects what has to run for it (nothing, most of the time)
fn prepare(event: &str, extra: &[(&str, String)], with_all: bool) -> Option<Prepared> {
    let mut guard = STATE.lock().unwrap();
    let state = guard.as_mut()?;
    if !defs(&state.command).iter().any(|d| d.name == event) {
        return None;
    }

    state.seq += 1;
    let index = {
        let count = state.counts.entry(event.to_string()).or_insert(0);
        *count += 1;
        *count
    };

    if state.nested {
        return None;
    }

    let specific = variable(&state.command, event);
    let mut triggers = vec![specific.clone()];
    if with_all {
        triggers.push(variable(&state.command, "ALL"));
        triggers.push("GITS_ALL".to_string());
    }

    let mut calls = Vec::new();
    for trigger in triggers {
        if let Some(script) = env(&trigger) {
            calls.push(Call {
                trigger: trigger.clone(),
                from: "env",
                script,
            });
        }
        if let Some(script) = state.from_config.get(&trigger) {
            if !script.trim().is_empty() {
                calls.push(Call {
                    trigger: trigger.clone(),
                    from: "config",
                    script: script.trim().to_string(),
                });
            }
        }
    }

    let mut vars: Vec<(String, String)> = state
        .context
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    for (name, value) in extra {
        vars.push((name.to_string(), value.clone()));
    }
    vars.push(("GITS_EVENT".to_string(), specific));
    vars.push(("GITS_EVENT_NAME".to_string(), event.to_string()));
    vars.push(("GITS_EVENT_COMMAND".to_string(), state.command.clone()));
    vars.push(("GITS_EVENT_SEQ".to_string(), state.seq.to_string()));
    vars.push(("GITS_EVENT_INDEX".to_string(), index.to_string()));
    vars.push((
        "GITS_EVENT_CAN_STOP".to_string(),
        if can_stop(event) { "1" } else { "0" }.to_string(),
    ));
    vars.push((ENV_RUNNING.to_string(), "1".to_string()));

    Some(Prepared {
        shell: config::shell(),
        pwd: state.pwd.clone(),
        vars,
        calls,
        stdout_to_stderr: state.stdout_to_stderr,
        command: state.command.clone(),
    })
}

// "~/x" -> home, a relative path is relative to the directory gits was called in
fn script_path(script: &str, pwd: &Path) -> PathBuf {
    let path = expand_tilde(script);
    if path.is_absolute() {
        path
    } else {
        pwd.join(path)
    }
}

fn options<'a>(prepared: &Prepared, call: &Call, path: &Path) -> Options<'a> {
    let mut options = Options::new().pwd(&prepared.pwd);
    for (name, value) in &prepared.vars {
        options = options.env(name, value);
    }
    options
        .env("GITS_EVENT_TRIGGER", &call.trigger)
        .env("GITS_EVENT_TRIGGER_FROM", call.from)
        .env("GITS_EVENT_SCRIPT", path)
}

/**
 * Fires one event: runs every script registered for it (the one of the event, of *_ALL of the
 * command, of GITS_ALL; from the environment and from the config).
 * `args`: arguments of the event, given to the script after <EVENT> <command>.
 * Err: a script of START / BEFORE_* failed, the command has to stop.
 */
pub fn fire(event: &str, args: &[String], extra: &[(&str, String)]) -> Result<(), String> {
    let Some(prepared) = prepare(event, extra, true) else {
        return Ok(());
    };

    for call in &prepared.calls {
        let path = script_path(&call.script, &prepared.pwd);
        let problem = if !path.is_file() {
            Some(format!("script >{}< doesn't exist", path.display()))
        } else {
            let mut all: Vec<String> = vec![
                path.display().to_string(),
                event.to_string(),
                prepared.command.clone(),
            ];
            all.extend(args.iter().cloned());

            let mut options = options(&prepared, call, &path).forward_stderr();
            options = if prepared.stdout_to_stderr {
                options.stdout_into_stderr()
            } else {
                options.forward_stdout()
            };

            match cli(&prepared.shell, &all, options) {
                Ok(out) if out.success() => None,
                Ok(out) => Some(format!(
                    "script >{}< ended with {}",
                    path.display(),
                    out.status()
                )),
                Err(e) => Some(format!(
                    "can't run >{}< with shell {}=>{}<: {e}",
                    path.display(),
                    config::ENV_SHELL,
                    prepared.shell
                )),
            }
        };

        if let Some(problem) = problem {
            let text = format!(
                "event {} ({}, defined in {}): {problem}",
                call.trigger, event, call.from
            );
            if can_stop(event) {
                return Err(format!("{text} - the command is stopped"));
            }
            eprintln!("{}", yellow(&format!("gits warning: {text}")));
        }
    }
    Ok(())
}

pub const ENV_START: &str = "GITS_START";
pub const ENV_EXIT: &str = "GITS_EXIT";

/**
 * GITS_START: a script which runs ONCE, as the first thing of a command which has lifecycle
 * events, just before its event START (so not for --help, --version, events, list or an unknown
 * command: nothing starts there). gits waits for it, and a script which fails or doesn't exist
 * stops the command before anything is done (GITS_EXIT still runs).
 *
 * The counterpart of GITS_EXIT, and like it not one of the events of a command: only the
 * environment defines it (not a config), *_ALL scripts are not called for it.
 * Like every script: not run by a gits which was started from inside of a script.
 *
 *   $1 START   $2 the command
 */
pub fn start(command: &str, pwd: &Path) -> Result<(), String> {
    // an unknown command has no events
    if defs(command).is_empty() {
        return Ok(());
    }
    match global(ENV_START, "START", command, pwd, None) {
        Some(problem) => Err(format!("{ENV_START}: {problem}")),
        None => Ok(()),
    }
}

/**
 * GITS_EXIT: a script which runs as the very last thing of EVERY start of gits, like
 * `trap ... EXIT` of a shell: after a command which succeeded or failed, after Ctrl+C, SIGTERM and
 * SIGHUP (not after kill -9: nothing can run then), also after --help, an unknown command or a
 * command which has no lifecycle events. After the event END, when everything temporary is gone.
 *
 * Not one of the events of a command: only the environment defines it (not a config), *_ALL
 * scripts are not called for it, it can't change the exit code, and its failure is a warning.
 * Like every script: not run by a gits which was started from inside of a script.
 *
 *   $1 EXIT   $2 the command ("" when there was none)   $3 the exit code
 */
pub fn exit(command: &str, pwd: &Path, code: i32) {
    if let Some(problem) = global(ENV_EXIT, "EXIT", command, pwd, Some(code)) {
        eprintln!(
            "{}",
            yellow(&format!("gits warning: {ENV_EXIT}: {problem}"))
        );
    }
}

// the script of GITS_START (code: None) or GITS_EXIT (code: the exit code of gits).
// Some: what went wrong
fn global(variable: &str, name: &str, command: &str, pwd: &Path, code: Option<i32>) -> Option<String> {
    if env(ENV_RUNNING).is_some() {
        return None;
    }
    let script = env(variable)?;
    let path = script_path(&script, pwd);
    if !path.is_file() {
        return Some(format!("script >{}< doesn't exist", path.display()));
    }
    // what the events of the command knew (empty when the command has no events)
    let context: Vec<(String, String)> = STATE
        .lock()
        .unwrap()
        .as_ref()
        .map(|s| s.context.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
        .unwrap_or_default();
    let mut options = Options::new().pwd(pwd).forward_stderr();
    for (name, value) in &context {
        options = options.env(name, value);
    }
    let mut all = vec![
        path.display().to_string(),
        name.to_string(),
        command.to_string(),
    ];
    if let Some(code) = code {
        options = options.env("GITS_EVENT_EXIT_CODE", code.to_string());
        all.push(code.to_string());
    }
    // stdout of gits can be data (isinsync, list, find): what the script prints goes to stderr
    options = options
        .env("GITS_EVENT", variable)
        .env("GITS_EVENT_NAME", name)
        .env("GITS_EVENT_COMMAND", command)
        .env("GITS_EVENT_PWD", pwd)
        .env("GITS_EVENT_CAN_STOP", if code.is_none() { "1" } else { "0" })
        .env("GITS_EVENT_TRIGGER", variable)
        .env("GITS_EVENT_TRIGGER_FROM", "env")
        .env("GITS_EVENT_SCRIPT", &path)
        .env(ENV_RUNNING, "1")
        .stdout_into_stderr();
    let shell = config::shell();
    match cli(&shell, &all, options) {
        Ok(out) if out.success() => None,
        Ok(out) => Some(format!(
            "script >{}< ended with {}",
            path.display(),
            out.status()
        )),
        Err(e) => Some(format!(
            "can't run >{}< with shell {}=>{shell}<: {e}",
            path.display(),
            config::ENV_SHELL
        )),
    }
}

// for the places which can't stop anyway (cleanup, the end)
pub fn fire_quietly(event: &str, args: &[String], extra: &[(&str, String)]) {
    if let Err(e) = fire(event, args, extra) {
        eprintln!("{}", red(&format!("gits error: {e}")));
    }
}

/**
 * A replaceable event: the script of the user (GITS_<COMMAND>_<EVENT>, only from the environment:
 * these run before any config is known) or else `default`, the script built into gits.
 * Returns what the script printed. *_ALL scripts are not called for these events.
 */
pub fn replace(event: &str, default: &str, args: &[String]) -> Result<String, String> {
    let (shell, pwd, command, vars, user) = {
        let prepared = prepare(event, &[], false);
        match prepared {
            Some(mut p) => {
                let user = if p.calls.is_empty() {
                    None
                } else {
                    Some(p.calls.remove(0))
                };
                (p.shell, p.pwd, p.command, p.vars, user)
            }
            // nested gits, or the event doesn't belong to the command: the default, no context
            None => {
                let guard = STATE.lock().unwrap();
                let pwd = guard
                    .as_ref()
                    .map(|s| s.pwd.clone())
                    .unwrap_or_else(|| PathBuf::from("."));
                let command = guard
                    .as_ref()
                    .map(|s| s.command.clone())
                    .unwrap_or_default();
                (config::shell(), pwd, command, Vec::new(), None)
            }
        }
    };

    let mut options = Options::new().pwd(&pwd).forward_stderr();
    for (name, value) in &vars {
        options = options.env(name, value);
    }

    let out = match &user {
        Some(call) => {
            let path = script_path(&call.script, &pwd);
            if !path.is_file() {
                return Err(format!(
                    "event {}: script >{}< doesn't exist",
                    call.trigger,
                    path.display()
                ));
            }
            let mut all: Vec<String> = vec![path.display().to_string(), event.to_string(), command];
            all.extend(args.iter().cloned());
            let options = options
                .env("GITS_EVENT_TRIGGER", &call.trigger)
                .env("GITS_EVENT_TRIGGER_FROM", call.from)
                .env("GITS_EVENT_SCRIPT", &path);
            cli(&shell, &all, options).map_err(|e| {
                format!(
                    "can't run >{}< with shell {}=>{shell}<: {e}",
                    path.display(),
                    config::ENV_SHELL
                )
            })?
        }
        None => {
            // the same arguments a script file gets: $1 event, $2 command, $3...
            let mut all: Vec<String> = vec![
                "-c".to_string(),
                default.to_string(),
                "gits".to_string(),
                event.to_string(),
                command,
            ];
            all.extend(args.iter().cloned());
            let options = options
                .env("GITS_EVENT_TRIGGER", "")
                .env("GITS_EVENT_TRIGGER_FROM", "default")
                .env("GITS_EVENT_SCRIPT", "");
            cli(&shell, &all, options).map_err(|e| {
                format!(
                    "can't run the default script of event {event} with shell {}=>{shell}<: {e}",
                    config::ENV_SHELL
                )
            })?
        }
    };

    if !out.success() {
        let which = match &user {
            Some(call) => format!("script >{}< of event {}", call.script, call.trigger),
            None => format!("the default script of event {event}"),
        };
        return Err(format!("{which} ended with {}", out.status()));
    }
    Ok(out.stdout_text())
}

// ---------------------------------------------------------------------------------------------
// gits events
// ---------------------------------------------------------------------------------------------

fn kind_text(def: &Def) -> &'static str {
    match def.kind {
        Kind::Replace => "replaces a default",
        Kind::Notify if can_stop(def.name) => "can stop the command",
        Kind::Notify => "",
    }
}

// every variable a script can be registered with, in the order of "gits events": (name, replaces a default)
pub fn variables() -> Vec<(String, bool)> {
    let mut out = vec![("GITS_ALL".to_string(), false)];
    for (command, defs) in REGISTRY {
        out.push((variable(command, "ALL"), false));
        for def in *defs {
            out.push((variable(command, def.name), def.kind == Kind::Replace));
        }
    }
    out
}

// every event of every command and what is defined right now
pub fn table() -> String {
    let mut out = String::new();
    out.push_str(
        "\nLifecycle events: a script registered for an event runs when gits reaches it.\n\
         The value of a variable is the path of a script, run by the shell from GITS_SHELL.\n\
         Everything about them: LIFECYCLE.md, examples of every script: events/examples/\n\n",
    );
    let shown = |name: &str| -> String {
        match env(name) {
            Some(value) => value,
            None => "-".to_string(),
        }
    };
    out.push_str(&format!("  {:<28} {}\n", "GITS_ALL", shown("GITS_ALL")));
    out.push_str("      every event of every command\n\n");
    out.push_str(&format!("  {:<28} {}\n", ENV_START, shown(ENV_START)));
    out.push_str(
        "      not an event: once, the first thing of a command which has events, before its START. Can stop it\n\n",
    );
    out.push_str(&format!("  {:<28} {}\n", ENV_EXIT, shown(ENV_EXIT)));
    out.push_str(
        "      not an event: the last thing of every start of gits, however it ends (like trap EXIT)\n\n",
    );

    for (command, defs) in REGISTRY {
        let title = if *command == "update" {
            "gits --update".to_string()
        } else {
            format!("gits {command}")
        };
        out.push_str(&format!("{title}\n"));
        let all = variable(command, "ALL");
        out.push_str(&format!("  {:<28} {}\n", all, shown(&all)));
        out.push_str("      every event of this command\n");
        for def in *defs {
            let name = variable(command, def.name);
            let note = kind_text(def);
            let note = if note.is_empty() {
                String::new()
            } else {
                format!("   ({note})")
            };
            out.push_str(&format!("  {:<28} {}{note}\n", name, shown(&name)));
            out.push_str(&format!("      {}\n", def.when));
        }
        out.push('\n');
    }
    out.push_str(
        "  \"-\" : not defined in the environment (the config of a project can define them too)\n",
    );
    out
}

fn comment(text: &str, width: usize) -> String {
    let mut out = String::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        if !line.is_empty() && line.len() + 1 + word.len() > width {
            out.push_str(&format!("# {line}\n"));
            line.clear();
        }
        if !line.is_empty() {
            line.push(' ');
        }
        line.push_str(word);
    }
    if !line.is_empty() {
        out.push_str(&format!("# {line}\n"));
    }
    out
}

fn var_lines(vars: &[(&str, &str)]) -> String {
    let width = vars.iter().map(|(n, _)| n.len()).max().unwrap_or(0);
    let mut out = String::new();
    for (name, meaning) in vars {
        out.push_str(&format!("#   {name:<width$}   {meaning}\n"));
    }
    out
}

fn title(command: &str) -> String {
    if command == "update" {
        "gits --update".to_string()
    } else {
        format!("gits {command}")
    }
}

// the example script of one event: what it is, what it gets, and a body which shows it
pub fn example(command: &str, def: &Def) -> String {
    let name = variable(command, def.name);
    let mut out = String::new();
    out.push_str("#\n");
    out.push_str(&format!(
        "# Example script of the lifecycle event {name}   ({}, event {})\n#\n",
        title(command),
        def.name
    ));
    out.push_str("# When:\n");
    out.push_str(&comment(def.when, 96).replace("# ", "#   "));
    out.push_str(&format!("#   Fired: {}.\n#\n", def.fired));

    match def.kind {
        Kind::Replace => {
            out.push_str(
                "# This event is REPLACEABLE: the script does a part of the work of gits and gits reads\n\
                 # what it prints on stdout. When the variable is not defined, the default script built\n\
                 # into gits runs: events/defaults/FIND.sh. A non-zero exit code is an error of the command.\n\
                 # GITS_<COMMAND>_ALL and GITS_ALL are not called for this event.\n#\n",
            );
        }
        Kind::Notify if can_stop(def.name) => {
            out.push_str(
                "# This script CAN STOP the command: when it ends with a non-zero exit code, gits\n\
                 # reports it and does not continue (the temporary directory is still removed, and\n\
                 # the events ERROR and END still fire).\n#\n",
            );
        }
        Kind::Notify => {
            out.push_str(
                "# This script can't stop the command: a non-zero exit code is only reported as a warning.\n#\n",
            );
        }
    }

    out.push_str("# Register it (the value is the path of the script, ~/ means your home):\n#\n");
    out.push_str(&format!(
        "#   export {name}=\"~/.gits/events/{name}.sh\"        in ~/.zshrc or ~/.bashrc\n"
    ));
    if def.kind == Kind::Notify
        && def.name != "START"
        && !(command == "state" && def.name == "FOUND")
    {
        out.push_str(&format!(
            "#   {name}=\"~/.gits/events/{name}.sh\"               or in .git/gits.sh of a project\n"
        ));
    }
    out.push_str("#\n# It is executed by the shell from GITS_SHELL (default /bin/bash), in the directory where\n# gits was called:\n#\n");
    let mut call = format!("#   $GITS_SHELL <this script> {} {}", def.name, command);
    for arg in def.args {
        call.push_str(&format!(" \"<{arg}>\""));
    }
    out.push_str(&format!(
        "{call}\n#\n# Arguments:\n#   $1   {}\n#   $2   {command}\n",
        def.name
    ));
    for (i, arg) in def.args.iter().enumerate() {
        out.push_str(&format!("#   ${}   {arg}\n", i + 3));
    }
    if !def.vars.is_empty() {
        out.push_str("#\n# Env vars of this event:\n");
        out.push_str(&var_lines(def.vars));
    }
    out.push_str("#\n# Env vars of every event:\n");
    out.push_str(&var_lines(ALWAYS));
    out.push_str("#\n# Env vars which exist from the moment gits knows them (empty before):\n");
    out.push_str(&var_lines(ONCE_KNOWN));
    out.push_str(
        "#\n# stdout and stderr of the script are shown as they come (gits isinsync: both on stderr).\n\
         # gits called from inside of this script runs no scripts itself.\n#\n\n",
    );

    match def.kind {
        Kind::Replace => {
            out.push_str(
                "# the same as the default, plus: directories named \"vendor\" are not entered either\n\
                 find \"${3:-.}\" \\\n    -type d \\( -name node_modules -o -name vendor \\) -prune \\\n    -o -type f \\( -path '*/.git/gits.sh' -o -path '*/.git/gitstorage-config.sh' \\) -print\n",
            );
        }
        Kind::Notify => {
            out.push_str(&format!(
                "echo \"[${{GITS_EVENT_SEQ}}] ${{GITS_EVENT}} #${{GITS_EVENT_INDEX}}: {}\"\n",
                match def.args.len() {
                    0 => "pwd=${GITS_EVENT_PWD}".to_string(),
                    _ => (0..def.args.len())
                        .map(|i| format!("${{{}}}", i + 3))
                        .collect::<Vec<_>>()
                        .join(" "),
                }
            ));
            if can_stop(def.name) {
                out.push_str("\n# exit 1    <- would stop the command here\n");
            }
        }
    }
    out
}

fn example_all(command: Option<&str>) -> String {
    let (name, scope) = match command {
        Some(c) => (
            variable(c, "ALL"),
            format!("every event of \"{}\"", title(c)),
        ),
        None => (
            "GITS_ALL".to_string(),
            "every event of every command".to_string(),
        ),
    };
    let mut out = String::new();
    out.push_str(&format!(
        "#\n# Example script of {name}: it runs for {scope}\n\
         # (in addition to the script of the event itself, after it).\n#\n\
         # Which event it is this time:\n\
         #   $1 / GITS_EVENT_NAME      the event, e.g. BEFORE_COPY\n\
         #   $2 / GITS_EVENT_COMMAND   the command, e.g. push\n\
         #   GITS_EVENT                the variable of the event, e.g. GITS_PUSH_BEFORE_COPY\n\
         #   GITS_EVENT_TRIGGER        {name}: the variable which pointed to this script\n\
         #   GITS_EVENT_SEQ            number of the event in this run, from 1\n\
         #   GITS_EVENT_INDEX          which occurrence of this event, from 1\n\
         #   $3...                     arguments of the event (see the example script of that event)\n#\n\
         # A non-zero exit code stops the command when the event is START or BEFORE_*\n\
         # (GITS_EVENT_CAN_STOP is 1 then), otherwise it is only reported.\n\
         # Replaceable events (FIND) don't call this script.\n#\n\
         # Register it (the value is the path of the script, ~/ means your home):\n#\n\
         #   export {name}=\"~/.gits/events/{name}.sh\"        in ~/.zshrc or ~/.bashrc\n\
         #   {name}=\"~/.gits/events/{name}.sh\"               or in .git/gits.sh of a project\n#\n\
         # Env vars of every event:\n"
    ));
    out.push_str(&var_lines(ALWAYS));
    out.push_str("#\n# Env vars which exist from the moment gits knows them (empty before):\n");
    out.push_str(&var_lines(ONCE_KNOWN));
    out.push_str(
        "#\n# Env vars of single events: see the example script of each event.\n#\n\n\
         # one line per event into a log\n\
         echo \"$(date '+%Y-%m-%d %H:%M:%S') [${GITS_EVENT_SEQ}] ${GITS_EVENT} #${GITS_EVENT_INDEX} ${*:3}\" >> \"${HOME}/.gits/events.log\"\n",
    );
    out
}

// events/examples/: one script per event of every command, plus the *_ALL ones
pub fn examples() -> Vec<(String, String)> {
    let mut out = vec![("GITS_ALL.sh".to_string(), example_all(None))];
    for (command, defs) in REGISTRY {
        out.push((
            format!("{}.sh", variable(command, "ALL")),
            example_all(Some(command)),
        ));
        for def in *defs {
            out.push((
                format!("{}.sh", variable(command, def.name)),
                example(command, def),
            ));
        }
    }
    out
}

pub fn write_examples(dir: &Path) -> Result<usize, String> {
    fs::create_dir_all(dir).map_err(|e| format!("can't create >{}<: {e}", dir.display()))?;
    let all = examples();
    for (name, content) in &all {
        let path = dir.join(name);
        fs::write(&path, content).map_err(|e| format!("can't write >{}<: {e}", path.display()))?;
    }
    Ok(all.len())
}

// the reference chapter of LIFECYCLE.md
pub fn markdown() -> String {
    let mut out = String::new();
    let table = |vars: &[(&str, &str)]| -> String {
        let mut t = String::from("| Variable | Value |\n|---|---|\n");
        for (name, meaning) in vars {
            t.push_str(&format!("| `{name}` | {} |\n", meaning.replace('|', "\\|")));
        }
        t
    };
    out.push_str("### Env vars of every event\n\n");
    out.push_str(&table(ALWAYS));
    out.push_str("\n### Env vars which exist from the moment gits knows them\n\n");
    out.push_str(&table(ONCE_KNOWN));
    for (command, defs) in REGISTRY {
        out.push_str(&format!("\n### Events of `{}`\n\n", title(command)));
        out.push_str("| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |\n|---|---|---|---|---|\n");
        for def in *defs {
            let args = if def.args.is_empty() {
                "—".to_string()
            } else {
                def.args
                    .iter()
                    .enumerate()
                    .map(|(i, a)| format!("`${}` {a}", i + 3))
                    .collect::<Vec<_>>()
                    .join("<br>")
            };
            let vars = if def.vars.is_empty() {
                "—".to_string()
            } else {
                def.vars
                    .iter()
                    .map(|(n, m)| format!("`{n}` {m}"))
                    .collect::<Vec<_>>()
                    .join("<br>")
            };
            let note = kind_text(def);
            let note = if note.is_empty() {
                String::new()
            } else {
                format!(" **{note}**")
            };
            out.push_str(&format!(
                "| `{}` | {}{note} | {} | {args} | {vars} |\n",
                variable(command, def.name),
                def.when,
                def.fired
            ));
        }
    }
    out
}

pub fn run(args: &[String]) -> Result<i32, String> {
    match args.first().map(|s| s.as_str()) {
        None => {
            print!("{}", table());
            Ok(0)
        }
        Some("--examples") => {
            let dir = args.get(1).ok_or_else(|| {
                "usage: gits events --examples <directory>   (writes the example script of every event there)"
                    .to_string()
            })?;
            let count = write_examples(Path::new(dir))?;
            println!("{count} example scripts written to {dir}");
            Ok(0)
        }
        Some("--markdown") => {
            print!("{}", markdown());
            Ok(0)
        }
        Some(other) => Err(format!(
            "unknown argument >{other}<, usage: gits events | gits events --examples <directory> | gits events --markdown"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(
            variable("push", "BEFORE_ENCRYPT"),
            "GITS_PUSH_BEFORE_ENCRYPT"
        );
        assert_eq!(variable("update", "ALL"), "GITS_UPDATE_ALL");
        assert!(can_stop("START"));
        assert!(can_stop("BEFORE_PUSH"));
        assert!(!can_stop("AFTER_PUSH"));
        assert!(!can_stop("END"));
    }

    #[test]
    fn registry_is_sane() {
        for (command, defs) in REGISTRY {
            let mut seen = std::collections::HashSet::new();
            for def in *defs {
                assert!(seen.insert(def.name), "{command}: {} twice", def.name);
                // a name of an event must not look like a variable gits reads for something else
                assert!(crate::util::old_name(&variable(command, def.name)).is_none());
            }
            for must in ["START", "ERROR", "END"] {
                assert!(seen.contains(must), "{command}: no {must}");
            }
        }
    }

    #[test]
    fn examples_for_everything() {
        let all = examples();
        let events: usize = REGISTRY.iter().map(|(_, defs)| defs.len()).sum();
        assert_eq!(all.len(), 1 + REGISTRY.len() + events);
        let (_, text) = all
            .iter()
            .find(|(name, _)| name == "GITS_PUSH_BEFORE_ENCRYPT.sh")
            .unwrap();
        assert!(text.contains("GITS_EVENT_FILE_PLAIN"));
        assert!(text.contains("CAN STOP"));
        assert!(text.contains("#   $3   local file (absolute)"));
    }
}
