# Lifecycle events

Every gits command is a chain of stages: read the config, clone the storage, copy files,
compare, commit, push, clean up. **Between the stages gits can run your scripts.** A script can
look at what is going on (log it, notify you, check something) and, before a stage, say "stop".

This file is everything about them: how to register a script, what happens in which order in
every command (with graphs), and what each script gets.

- [In one minute](#in-one-minute)
- [The rules](#the-rules)
- [Where a script is registered: environment or the config of a project](#where-a-script-is-registered)
- [Stopping a command](#stopping-a-command)
- [Which event is it? The numbering](#which-event-is-it-the-numbering)
- [Replaceable events and their defaults](#replaceable-events-and-their-defaults)
- [The lifecycle of every command](#the-lifecycle-of-every-command)
- [Recipes](#recipes)
- [Reference: every event, its arguments and env vars](#reference)
- [Where to look next](#where-to-look-next)

## In one minute

```sh
mkdir -p ~/.gits/events

# 1. a script: it gets everything gits knows as GITS_EVENT_* env vars
cat > ~/.gits/events/after-push.sh <<'EEE'
echo "stored: commit ${GITS_EVENT_COMMIT} of ${GITS_TARGETDIR}"
EEE

# 2. register it: the name of the variable is GITS_<COMMAND>_<EVENT>, the value is the path
export GITS_PUSH_AFTER_PUSH="~/.gits/events/after-push.sh"

# 3. it runs when "gits push --yes" has pushed
gits push --yes
```

```sh
gits events                                        # every event of every command, and which ones have a script right now
gits events --examples ~/.gits/events-examples     # an example script of every event, documented at its top
```

The same example scripts are in this repository: [events/examples/](events/examples/).

## The rules

1. **The name** of the variable is `GITS_<COMMAND>_<EVENT>`: `GITS_PUSH_BEFORE_PUSH`,
   `GITS_DIFF_AFTER_COMPARE`, `GITS_STATE_END`. `<COMMAND>` is one of `STATE FIND INIT ADD DIFF
   ISINSYNC PUSH PULL URL MOVE MIGRATE UPDATE` (`UPDATE` is `gits --update`).
2. **The value is the path of a script.** `~/` at its beginning is your home. A relative path
   is relative to the directory where gits was called. It is not a command line: no arguments,
   no pipes; put those into the script.
3. **The script is executed by the shell from `GITS_SHELL`** (default `/bin/bash`), the same
   shell which runs `.git/gits.sh`. It needs no shebang and no executable bit:

   ```
   $GITS_SHELL <script> <EVENT> <command> [arguments of the event]
   ```

   Inside of the script you can start anything (node, python, curl).
4. **Working directory** of the script: the directory where gits was called.
5. **What it gets:** `$1` the event (`BEFORE_PUSH`), `$2` the command (`push`), then the
   arguments of the event; and env vars: everything gits knows at that moment, see
   [Reference](#reference).
6. **Output:** stdout and stderr of the script are shown as they come. In `gits isinsync`
   (which never prints on stdout) both go to stderr.
7. **An event without a script costs nothing:** no process is started.
8. **Catch-all variables** run a script for many events, in addition to the script of the event:

   | Variable | Runs for |
   |---|---|
   | `GITS_<COMMAND>_ALL` | every event of that command, e.g. `GITS_PUSH_ALL` |
   | `GITS_ALL` | every event of every command |

   Order for one event: the script of the event, then of `GITS_<COMMAND>_ALL`, then of `GITS_ALL`.
9. **No recursion:** gits started from inside of a script runs no scripts itself (the script
   has `GITS_EVENT_RUNNING=1` in its environment, the inner gits sees it).

## Where a script is registered

Two places, and both can be used at once:

| Where | For | Example |
|---|---|---|
| the environment (`~/.zshrc`, `~/.bashrc`) | all your projects | `export GITS_PUSH_AFTER_PUSH="~/.gits/events/after-push.sh"` |
| `.git/gits.sh` of a project | that project only | `GITS_PUSH_BEFORE_PUSH=".git/check-before-push.sh"` |

The config is a shell script, so a variable defined in it is all it takes (no `export` needed):

```bash
GITS_TARGETDIR="git@github.com:owner__repo.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "check-before-push.sh::$GITS_TARGETDIR/check-before-push.sh"     # the script travels with the config
    "../.env::$GITS_TARGETDIR/.env"
)

# relative to the root of the project: that is where gits is called
GITS_PUSH_BEFORE_PUSH=".git/check-before-push.sh"
GITS_DIFF_ALL=".git/log-events.sh"
```

- gits knows the config only after it executed it: scripts of the config run **from the event
  `CONFIG_LOADED` on**. `START` can only come from the environment.
- When the same event is defined in both places, both scripts run: the environment first.
  `GITS_EVENT_TRIGGER_FROM` tells the script which one it is (`env` or `config`).
- `gits state` checks many projects: the scripts of a config run only while its project is checked.
- A script named in a config is a program which runs on your machine with your rights, like
  the config itself. Look at what a config contains before you `gits pull --yes` it from a
  storage you don't control.

## Stopping a command

| Event | When its script ends with a non-zero exit code |
|---|---|
| `START`, `BEFORE_*` | **the command is stopped.** gits prints which script said no and ends with exit code 1 (`isinsync`: 2). The temporary directory is still removed; `ERROR` and `END` still fire |
| `AFTER_*`, `END`, `ERROR`, `CONFIG_LOADED`, `FOUND` | only a warning (`gits warning: event ...`), the command continues and its exit code is not changed |
| replaceable (`FIND`) | an error of the command: the work of that stage was not done |

A variable which points to a file which doesn't exist is treated as a script which failed.

`GITS_EVENT_CAN_STOP` is `1` in a script whose failure stops the command, else `0`.

## Which event is it? The numbering

One script can serve many events (`GITS_ALL`), and one event can fire many times (`BEFORE_COPY`
for every file). The script always knows where it is:

| Variable | Example | Meaning |
|---|---|---|
| `GITS_EVENT` | `GITS_PUSH_BEFORE_COPY` | the variable of this event, also when the script runs through `*_ALL` |
| `GITS_EVENT_NAME` | `BEFORE_COPY` | the event (also `$1`) |
| `GITS_EVENT_COMMAND` | `push` | the command (also `$2`) |
| `GITS_EVENT_SEQ` | `7` | number of this event among **all** events of this run, from 1. Events without a script are counted too, so the numbers are the same whatever is registered |
| `GITS_EVENT_INDEX` | `2` | which occurrence of **this** event: `BEFORE_COPY` of the second file is `2` |
| `GITS_EVENT_TRIGGER` | `GITS_ALL` | the variable which pointed to this script |
| `GITS_EVENT_TRIGGER_FROM` | `env` | where that variable was defined: `env` or `config` |

For the per-file events `GITS_EVENT_FILE_INDEX` is the position of the file in `GITS_LIST`.

## Replaceable events and their defaults

Most events only tell your script that something happened. A **replaceable** event is a stage
of gits which is itself a script: gits runs it and reads what it prints. Without a variable
the default script runs; with one, yours runs instead.

| Variable | Stage | Default |
|---|---|---|
| `GITS_STATE_FIND` | `gits state`: which projects to check | [events/defaults/FIND.sh](events/defaults/FIND.sh) |
| `GITS_FIND_FIND` | `gits find`: which projects to list | [events/defaults/FIND.sh](events/defaults/FIND.sh) |
| `GITS_MIGRATE_FIND` | `gits migrate all`: which projects to look at | [events/defaults/FIND.sh](events/defaults/FIND.sh) |

The default is a `find` which never enters `node_modules`:

```sh
find . -type d -name node_modules -prune -o -type f \( -path '*/.git/gits.sh' -o -path '*/.git/gitstorage-config.sh' \) -print
```

The contract is at the top of that file: print the path of every config, one per line; gits
keeps only the ones which really are a config in a real `.git` directory, sorts them and removes
duplicates. Your own version, for example to skip more directories:

```sh
cat > ~/.gits/events/find.sh <<'EEE'
find "${3:-.}" \
    -type d \( -name node_modules -o -name vendor -o -name target \) -prune \
    -o -type f \( -path '*/.git/gits.sh' -o -path '*/.git/gitstorage-config.sh' \) -print
EEE
export GITS_STATE_FIND="~/.gits/events/find.sh"
export GITS_FIND_FIND="~/.gits/events/find.sh"
```

- The defaults are compiled into the binary, the files in `events/defaults/` are their source.
- These variables are read from the environment only: at that stage no config is known yet.
- `GITS_<COMMAND>_ALL` and `GITS_ALL` are not called for a replaceable event (they could not do
  its work), but the event is counted in `GITS_EVENT_SEQ`.

## The lifecycle of every command

How to read the graphs: top to bottom is time. `[ ... ]` is a stage of gits, a name on its own
line is an event. `<-- (stop)` marks the events whose script can stop the command.
`START`, `ERROR` and `END` exist in every command:

```
  gits <command>
        |
        v
      START  <-- (stop)                     only scripts of the environment
        |
        v
   [ the command ] ----- it fails -----> [ the error message is printed ] --> ERROR
        |                                                                       |
        v                                                                       v
       END  <-- always the last one: the exit code is known, also after Ctrl+C (130)
```

When a command fails in the middle, the events of its remaining stages don't fire, except the
two around the removal of the temporary directory (`BEFORE_CLEANUP`, `AFTER_CLEANUP`), `ERROR` and `END`.

### gits diff, gits isinsync

Both do the same check; `isinsync` prints nothing and only its exit code matters.
`gits push` and `gits pull` without `--yes` are this check too (with their own names:
`GITS_PUSH_*`, `GITS_PULL_*`).

```
      START  <-- (stop)
        |
  [ execute .git/gits.sh ]
        |
   CONFIG_LOADED                             GITS_TARGETDIR and the list are known,
        |                                    scripts of the config run from here on
  [ create the temporary directory ]
        |
   BEFORE_CLONE  <-- (stop)
  [ git clone of the storage ]
   AFTER_CLONE
        |
        |   for every element SOURCE:e:TARGET which the storage has:
        |       BEFORE_DECRYPT  <-- (stop)
        |     [ decrypt the stored file inside of the clone ]
        |       AFTER_DECRYPT
        |
        |   for every element of the list:
        |       BEFORE_COPY  <-- (stop)
        |     [ copy the local file over the file in the clone ]
        |       AFTER_COPY
        |
   BEFORE_COMPARE  <-- (stop)
  [ git status of the clone: anything changed? ]
   AFTER_COMPARE                             GITS_EVENT_RESULT: insync | differs | missing
        |                                    GITS_EVENT_CHANGED: the local files which differ
  [ diff only: git diff, git status, the list of changed files, the url ]
        |
   BEFORE_CLEANUP                            the last moment to look into the clone
  [ remove the temporary directory ]
   AFTER_CLEANUP
        |
       END                                   exit code 0: in sync, 1: not (isinsync: 2 = error)
```

### gits push --yes

```
      START  <-- (stop)
        |
  [ execute .git/gits.sh ]
   CONFIG_LOADED
        |
  [ create the temporary directory ]
   BEFORE_CLONE  <-- (stop)
  [ git clone of the storage ]
   AFTER_CLONE
        |
        |   for every element of the list, in its order:
        |
        |     SOURCE::TARGET (plain)            SOURCE:e:TARGET (encrypted)
        |     ----------------------            ---------------------------
        |       BEFORE_COPY  <-- (stop)           when the storage has the file:
        |     [ copy into the clone ]               BEFORE_DECRYPT  <-- (stop)
        |       AFTER_COPY                        [ decrypt it, compare with the local file ]
        |                                           AFTER_DECRYPT
        |                                         when the content changed (or it is new):
        |                                         [ plain copy next to the stored file: TARGET.hash... ]
        |                                           BEFORE_ENCRYPT  <-- (stop)     GITS_EVENT_FILE_PLAIN
        |                                         [ the encoder process encrypts over the stored file,
        |                                           the plain copy is removed ]
        |                                           AFTER_ENCRYPT
        |
  [ git status: anything to store? ] ---- no ----> "files are in sync" ----.
        | yes                                                              |
   BEFORE_COMMIT  <-- (stop)                                               |
  [ git add, git commit in the clone ]                                     |
   AFTER_COMMIT                              GITS_EVENT_COMMIT             |
        |                                                                  |
   BEFORE_PUSH  <-- (stop)                   the last moment to refuse     |
  [ git push to the storage ]                                              |
   AFTER_PUSH                                the storage has the commit    |
        |                                                                  |
        |<-----------------------------------------------------------------'
   BEFORE_CLEANUP
  [ remove the temporary directory ]
   AFTER_CLEANUP
        |
       END
```

### gits pull --yes

```
      START  <-- (stop)
        |
  [ execute .git/gits.sh ]
   CONFIG_LOADED
        |
  [ create the temporary directory ]
   BEFORE_CLONE  <-- (stop)
  [ git clone of the storage ]
   AFTER_CLONE
        |
        |   the config first, when it is in its own list:
        |       BEFORE_COPY  <-- (stop)      (BEFORE_DECRYPT / AFTER_DECRYPT before it when it is :e:)
        |     [ stored config -> .git/gits.sh ]
        |       AFTER_COPY
        |     when it was different from the local one:
        |     [ execute the new .git/gits.sh ]
        |       CONFIG_LOADED                the second one of this run (GITS_EVENT_INDEX=2)
        |
        |   for every other element of the list:
        |
        |     SOURCE::TARGET (plain)            SOURCE:e:TARGET (encrypted)
        |     ----------------------            ---------------------------
        |       BEFORE_COPY  <-- (stop)           BEFORE_DECRYPT  <-- (stop)
        |     [ stored file -> local file ]     [ decrypt next to the stored file ]
        |       AFTER_COPY                        AFTER_DECRYPT
        |                                         BEFORE_COPY  <-- (stop)
        |                                       [ decrypted file -> local file ]
        |                                         AFTER_COPY
        |
   BEFORE_CLEANUP
  [ remove the temporary directory ]
   AFTER_CLEANUP
        |
       END
```

A file which the storage doesn't have fires no events.

### gits state

```
      START  <-- (stop)
        |
      FIND   <== replaceable: GITS_STATE_FIND, default events/defaults/FIND.sh
        |        (prints the configs below the current directory)
      FOUND                                  GITS_EVENT_FOUND: the projects, GITS_EVENT_FOUND_COUNT
        |
  [ create the temporary directory ]
        |
        |   for every project:                                   GITS_EVENT_STATE_INDEX / _COUNT
        |
        |       BEFORE_PROJECT  <-- (stop)                       GITS_EVENT_PROJECT_DIR
        |     [ execute its .git/gits.sh ]
        |       CONFIG_LOADED                                    its scripts run until AFTER_PROJECT
        |     [ the first project only: ]
        |         BEFORE_CLONE  <-- (stop)
        |       [ git clone of the storage ]
        |         AFTER_CLONE
        |     [ the others: the clone is reset to what was cloned ]
        |
        |       BEFORE_DECRYPT / AFTER_DECRYPT   per stored :e: file   \
        |       BEFORE_COPY / AFTER_COPY         per element            >  the check of "gits diff"
        |       BEFORE_COMPARE / AFTER_COMPARE                         /
        |
        |       AFTER_PROJECT                                    GITS_EVENT_RESULT: insync | differs | missing | error
        |                                                        GITS_EVENT_COUNT_SUCCESS / _ERROR so far
        |
   BEFORE_CLEANUP
  [ remove the temporary directory ]
   AFTER_CLEANUP
        |
       END                                   exit code 1 when any project is not in sync
```

A project whose config can't be read is counted as an error and `state` goes on with the next
one; its `AFTER_PROJECT` has `GITS_EVENT_RESULT=error`.

### gits find

```
      START  <-- (stop)
        |
      FIND   <== replaceable: GITS_FIND_FIND, default events/defaults/FIND.sh
        |
      FOUND
        |
  [ print the projects ]
        |
       END
```

### gits init

```
      START  <-- (stop)
        |
  [ .git/gits.sh exists already? then nothing to do ] ------------------.
        |                                                               |
  [ create the temporary directory ]                                    |
   BEFORE_CLONE  <-- (stop)                                             |
  [ git clone of the storage ]                                          |
   AFTER_CLONE                                                          |
        |                                                               |
  [ where does the config come from? ]                                  |
        |      storage:   it has one for this project                   |
        |      template:  GITS_TEMPLATE                                 |
        |      built-in:  the template of gits                          |
        |                                                               |
   BEFORE_WRITE  <-- (stop)                  GITS_EVENT_WRITE_ORIGIN    |
  [ write .git/gits.sh ]                                                |
   AFTER_WRITE                                                          |
        |                                                               |
   BEFORE_CLEANUP                                                       |
  [ remove the temporary directory ]                                    |
   AFTER_CLEANUP                                                        |
        |<--------------------------------------------------------------'
       END
```

### gits add

```
      START  <-- (stop)
        |
  [ read .git/gits.sh, find the files ]
        |
  [ when stdin is a terminal: the list to tick the files; left without ctrl+enter -> END ]
        |
  [ make the new lines ]
        |
        |   only when there is something to add:
   BEFORE_WRITE  <-- (stop)                  GITS_EVENT_WRITE_ORIGIN: number of new lines
  [ write .git/gits.sh ]
   AFTER_WRITE
        |
       END
```

### gits url

```
      START  <-- (stop)
  [ execute .git/gits.sh ]
   CONFIG_LOADED
  [ print the url ]
       END
```

### gits move

```
      START  <-- (stop)
  [ print the procedure ]
       END
```

### gits migrate, gits migrate all

```
      START  <-- (stop)
        |
        |   "migrate all" only:
        |       FIND   <== replaceable: GITS_MIGRATE_FIND, default events/defaults/FIND.sh
        |       FOUND
        |
        |   for every project with .git/gitstorage-config.sh ("migrate": the current one):
        |       BEFORE_RENAME  <-- (stop)    GITS_EVENT_RENAME_FROM, GITS_EVENT_RENAME_TO
        |     [ write .git/gits.sh, remove the old config ]
        |       AFTER_RENAME
        |
       END
```

### gits --update

The variables are `GITS_UPDATE_*`.

```
      START  <-- (stop)
        |
  [ which release? installed already? ask for confirmation ]
        |
   BEFORE_DOWNLOAD  <-- (stop)               GITS_EVENT_UPDATE_TAG, GITS_EVENT_UPDATE_INSTALLED
  [ download, compare the checksum, run the new binary ]
   AFTER_DOWNLOAD
        |
   BEFORE_REPLACE  <-- (stop)                the installed binary is still the old one
  [ replace the installed binary, run it ]
   AFTER_REPLACE
        |
       END
```

## Recipes

**A log of everything gits does**, one line per event:

```sh
cat > ~/.gits/events/log.sh <<'EEE'
echo "$(date '+%F %T') [${GITS_EVENT_SEQ}] ${GITS_EVENT} #${GITS_EVENT_INDEX} ${*:3}" >> ~/.gits/events.log
EEE
export GITS_ALL="~/.gits/events/log.sh"
```

**Refuse to push a file which still has a placeholder** (per project, in `.git/gits.sh`):

```sh
# .git/check-before-push.sh
if grep -q 'CHANGE_ME' "${GITS_EVENT_PROJECT_DIR}/.env"; then
    echo ".env still has CHANGE_ME in it"
    exit 1
fi
```

```bash
# .git/gits.sh
GITS_PUSH_BEFORE_PUSH=".git/check-before-push.sh"
```

**A notification when a push is done:**

```sh
# ~/.gits/events/after-push.sh
osascript -e "display notification \"${GITS_TARGETDIR}\" with title \"gits: stored\""
```

**Look into the temporary clone before it is removed:**

```sh
# ~/.gits/events/before-cleanup.sh
ls -la "${GITS_EVENT_STORAGE_DIR}"
read -r -p "press Enter to continue " < /dev/tty
```

**Which files differ, to open them** (after `gits diff`):

```sh
# ~/.gits/events/after-compare.sh
echo "${GITS_EVENT_CHANGED}" | while IFS= read -r FILE; do
    [ -n "${FILE}" ] && code "${FILE}"
done
```

**Walk through the list of a project:** `GITS_EVENT_LIST` has one element per line:
`e` or `p` (encrypted / plain), the local file, TARGET, separated by tabs.

```sh
while IFS=$'\t' read -r KIND SOURCE TARGET; do
    echo "${KIND} ${SOURCE} -> ${TARGET}"
done <<< "${GITS_EVENT_LIST}"
```

## Reference

Generated from the list of events in `src/events.rs` (`gits events --markdown`), the same
source `gits events` and the example scripts use.

The native variables (`GITS_SOURCE`, `GITS_SHELL`, `GITS_ENCRYPTION_SOCKET`, `GITS_TEMPLATE`,
`GITS_TARGETDIR`) are given to a script with the values gits itself uses: defaults applied, and
also when they came from the old names (`GITSTORAGESOURCE`, ...). Everything else of your
environment is inherited by the script as it is.

### Env vars of every event

| Variable | Value |
|---|---|
| `GITS_EVENT` | name of the variable of this event, e.g. GITS_PUSH_BEFORE_ENCRYPT (also when the script runs as *_ALL) |
| `GITS_EVENT_NAME` | the event, e.g. BEFORE_ENCRYPT |
| `GITS_EVENT_COMMAND` | the command, e.g. push |
| `GITS_EVENT_SEQ` | number of this event among all events of this run, from 1 (events without a script count too) |
| `GITS_EVENT_INDEX` | which occurrence of this event it is in this run, from 1 (BEFORE_COPY of the 3rd file: 3) |
| `GITS_EVENT_TRIGGER` | the variable which pointed to this script: the one of the event, GITS_<COMMAND>_ALL or GITS_ALL |
| `GITS_EVENT_TRIGGER_FROM` | where that variable was defined: env or config (.git/gits.sh) |
| `GITS_EVENT_SCRIPT` | path of this script |
| `GITS_EVENT_CAN_STOP` | 1: a non-zero exit code of this script stops the command (START, BEFORE_*). 0: it is only reported |
| `GITS_EVENT_RUNNING` | 1. gits started from inside of a script sees it and runs no scripts itself |
| `GITS_EVENT_PWD` | directory where gits was called |
| `GITS_EVENT_ARGS` | arguments gits was called with, separated by spaces |
| `GITS_EVENT_BIN` | path of the gits binary |
| `GITS_EVENT_VERSION` | version of gits |
| `GITS_EVENT_PID` | process id of gits |
| `GITS_SOURCE` | the storage, as gits uses it |
| `GITS_SHELL` | the shell which runs the config and the scripts |
| `GITS_ENCRYPTION_SOCKET` | socket of the encoder process (empty when not defined) |
| `GITS_TEMPLATE` | template of 'gits init' (empty when not defined) |

### Env vars which exist from the moment gits knows them

| Variable | Value |
|---|---|
| `GITS_EVENT_PROJECT_DIR` | root of the project (state: of the project which is checked right now) |
| `GITS_EVENT_CONFIG` | path of .git/gits.sh of the project |
| `GITS_TARGETDIR` | directory of the project in the storage, from the config |
| `GITS_EVENT_LIST_COUNT` | number of elements of GITS_LIST |
| `GITS_EVENT_LIST` | all elements, one per line: <e\|p><TAB>local file (absolute)<TAB>TARGET   (e: encrypted, p: plain) |
| `GITS_EVENT_TEMP_DIR` | the temporary directory: the clone of the storage |
| `GITS_EVENT_STORAGE_DIR` | directory of the project inside of the clone: <temporary directory>/<GITS_TARGETDIR> |
| `GITS_EVENT_STORAGE_BRANCH` | branch of the storage |
| `GITS_EVENT_YES` | 1 when --yes was given, else 0 |

### Events of `gits state`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_STATE_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_STATE_FIND` | the projects below the current directory have to be found. The script does it: it prints the path of every config (.git/gits.sh, .git/gitstorage-config.sh), one per line. Default: events/defaults/FIND.sh **replaces a default** | once | `$3` directory to search | — |
| `GITS_STATE_FOUND` | the projects are found | once | `$3` number of projects | `GITS_EVENT_FOUND_COUNT` number of projects<br>`GITS_EVENT_FOUND` directories of the projects, relative to GITS_EVENT_PWD, one per line |
| `GITS_STATE_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_STATE_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_STATE_BEFORE_PROJECT` | state: one project is about to be checked **can stop the command** | once per project | `$3` directory of the project<br>`$4` number of the project<br>`$5` number of projects | `GITS_EVENT_STATE_INDEX` number of the project, from 1<br>`GITS_EVENT_STATE_COUNT` number of projects |
| `GITS_STATE_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_STATE_BEFORE_DECRYPT` | one stored file of an element SOURCE:e:TARGET is about to be decrypted **can stop the command** | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_STATE_AFTER_DECRYPT` | that file was decrypted (or turned out to be stored not encrypted) | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_STATE_BEFORE_COPY` | one file is about to be copied: local file -> clone (pull --yes: clone -> local file) **can stop the command** | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_STATE_AFTER_COPY` | that file was copied | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_STATE_BEFORE_COMPARE` | all local files are in the clone, 'git status' which decides "in sync or not" is next **can stop the command** | once (state: once per project) | — | — |
| `GITS_STATE_AFTER_COMPARE` | it is known whether the local files and the storage are in sync | once (state: once per project) | `$3` result | `GITS_EVENT_RESULT` insync, differs, or missing (a local file of the list doesn't exist)<br>`GITS_EVENT_CHANGED` local files which differ from the storage, absolute paths, one per line |
| `GITS_STATE_AFTER_PROJECT` | state: that project was checked | once per project | `$3` directory of the project<br>`$4` result | `GITS_EVENT_STATE_INDEX` number of the project, from 1<br>`GITS_EVENT_STATE_COUNT` number of projects<br>`GITS_EVENT_RESULT` insync, differs, missing, or error (the project could not be checked)<br>`GITS_EVENT_COUNT_SUCCESS` projects in sync so far, this one included<br>`GITS_EVENT_COUNT_ERROR` projects not in sync or failed so far, this one included |
| `GITS_STATE_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_STATE_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_STATE_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_STATE_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits find`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_FIND_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_FIND_FIND` | the projects below the current directory have to be found. The script does it: it prints the path of every config (.git/gits.sh, .git/gitstorage-config.sh), one per line. Default: events/defaults/FIND.sh **replaces a default** | once | `$3` directory to search | — |
| `GITS_FIND_FOUND` | the projects are found | once | `$3` number of projects | `GITS_EVENT_FOUND_COUNT` number of projects<br>`GITS_EVENT_FOUND` directories of the projects, relative to GITS_EVENT_PWD, one per line |
| `GITS_FIND_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_FIND_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits init`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_INIT_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_INIT_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_INIT_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_INIT_BEFORE_WRITE` | .git/gits.sh is about to be written **can stop the command** | once, only when there is something to write | `$3` path of the config | `GITS_EVENT_WRITE_ORIGIN` init: storage, template or built-in. add: number of lines which are added |
| `GITS_INIT_AFTER_WRITE` | .git/gits.sh was written | once, only when there is something to write | `$3` path of the config | `GITS_EVENT_WRITE_ORIGIN` init: storage, template or built-in. add: number of lines which were added |
| `GITS_INIT_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_INIT_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_INIT_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_INIT_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits add`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_ADD_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_ADD_BEFORE_WRITE` | .git/gits.sh is about to be written **can stop the command** | once, only when there is something to write | `$3` path of the config | `GITS_EVENT_WRITE_ORIGIN` init: storage, template or built-in. add: number of lines which are added |
| `GITS_ADD_AFTER_WRITE` | .git/gits.sh was written | once, only when there is something to write | `$3` path of the config | `GITS_EVENT_WRITE_ORIGIN` init: storage, template or built-in. add: number of lines which were added |
| `GITS_ADD_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_ADD_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits diff`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_DIFF_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_DIFF_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_DIFF_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_DIFF_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_DIFF_BEFORE_DECRYPT` | one stored file of an element SOURCE:e:TARGET is about to be decrypted **can stop the command** | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_DIFF_AFTER_DECRYPT` | that file was decrypted (or turned out to be stored not encrypted) | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_DIFF_BEFORE_COPY` | one file is about to be copied: local file -> clone (pull --yes: clone -> local file) **can stop the command** | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_DIFF_AFTER_COPY` | that file was copied | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_DIFF_BEFORE_COMPARE` | all local files are in the clone, 'git status' which decides "in sync or not" is next **can stop the command** | once (state: once per project) | — | — |
| `GITS_DIFF_AFTER_COMPARE` | it is known whether the local files and the storage are in sync | once (state: once per project) | `$3` result | `GITS_EVENT_RESULT` insync, differs, or missing (a local file of the list doesn't exist)<br>`GITS_EVENT_CHANGED` local files which differ from the storage, absolute paths, one per line |
| `GITS_DIFF_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_DIFF_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_DIFF_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_DIFF_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits isinsync`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_ISINSYNC_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_ISINSYNC_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_ISINSYNC_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_ISINSYNC_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_ISINSYNC_BEFORE_DECRYPT` | one stored file of an element SOURCE:e:TARGET is about to be decrypted **can stop the command** | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_ISINSYNC_AFTER_DECRYPT` | that file was decrypted (or turned out to be stored not encrypted) | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_ISINSYNC_BEFORE_COPY` | one file is about to be copied: local file -> clone (pull --yes: clone -> local file) **can stop the command** | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_ISINSYNC_AFTER_COPY` | that file was copied | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_ISINSYNC_BEFORE_COMPARE` | all local files are in the clone, 'git status' which decides "in sync or not" is next **can stop the command** | once (state: once per project) | — | — |
| `GITS_ISINSYNC_AFTER_COMPARE` | it is known whether the local files and the storage are in sync | once (state: once per project) | `$3` result | `GITS_EVENT_RESULT` insync, differs, or missing (a local file of the list doesn't exist)<br>`GITS_EVENT_CHANGED` local files which differ from the storage, absolute paths, one per line |
| `GITS_ISINSYNC_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_ISINSYNC_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_ISINSYNC_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_ISINSYNC_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits push`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_PUSH_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_PUSH_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_PUSH_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_PUSH_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_PUSH_BEFORE_DECRYPT` | one stored file of an element SOURCE:e:TARGET is about to be decrypted **can stop the command** | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PUSH_AFTER_DECRYPT` | that file was decrypted (or turned out to be stored not encrypted) | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PUSH_BEFORE_COPY` | one file is about to be copied: local file -> clone (pull --yes: clone -> local file) **can stop the command** | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PUSH_AFTER_COPY` | that file was copied | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PUSH_BEFORE_COMPARE` | all local files are in the clone, 'git status' which decides "in sync or not" is next **can stop the command** | once (state: once per project) | — | — |
| `GITS_PUSH_AFTER_COMPARE` | it is known whether the local files and the storage are in sync | once (state: once per project) | `$3` result | `GITS_EVENT_RESULT` insync, differs, or missing (a local file of the list doesn't exist)<br>`GITS_EVENT_CHANGED` local files which differ from the storage, absolute paths, one per line |
| `GITS_PUSH_BEFORE_ENCRYPT` | push --yes: the plain copy of one file lies next to its stored file, encryption is next **can stop the command** | once per encrypted element whose content changed | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1<br>`GITS_EVENT_FILE_PLAIN` the temporary plain copy (TARGET.hash...), removed right after the encryption |
| `GITS_PUSH_AFTER_ENCRYPT` | push --yes: that file was encrypted over its stored file, the plain copy is removed | once per encrypted element whose content changed | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PUSH_BEFORE_COMMIT` | push --yes: the clone holds what is going to be stored, 'git add' + 'git commit' are next **can stop the command** | once, only when there is something to store | — | — |
| `GITS_PUSH_AFTER_COMMIT` | push --yes: the commit exists in the clone, it is not in the storage yet | once, only when there is something to store | `$3` commit hash | `GITS_EVENT_COMMIT` hash of the new commit |
| `GITS_PUSH_BEFORE_PUSH` | push --yes: 'git push' to the storage is next. The last moment to stop it **can stop the command** | once, only when there is something to store | `$3` commit hash | `GITS_EVENT_COMMIT` hash of the new commit |
| `GITS_PUSH_AFTER_PUSH` | push --yes: the storage has the new commit | once, only when there is something to store | `$3` commit hash | `GITS_EVENT_COMMIT` hash of the new commit |
| `GITS_PUSH_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_PUSH_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_PUSH_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_PUSH_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits pull`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_PULL_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_PULL_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_PULL_BEFORE_CLONE` | the temporary directory exists and is empty, 'git clone' of the storage is next **can stop the command** | once | `$3` temporary directory | — |
| `GITS_PULL_AFTER_CLONE` | the storage is cloned into the temporary directory | once | `$3` temporary directory | — |
| `GITS_PULL_BEFORE_DECRYPT` | one stored file of an element SOURCE:e:TARGET is about to be decrypted **can stop the command** | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PULL_AFTER_DECRYPT` | that file was decrypted (or turned out to be stored not encrypted) | once per encrypted element whose file is in the storage | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PULL_BEFORE_COPY` | one file is about to be copied: local file -> clone (pull --yes: clone -> local file) **can stop the command** | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PULL_AFTER_COPY` | that file was copied | once per element of the list | `$3` local file (absolute)<br>`$4` file in the temporary clone | `GITS_EVENT_FILE_SOURCE` the local file, absolute path<br>`GITS_EVENT_FILE_SOURCE_RAW` SOURCE as it is written in the config<br>`GITS_EVENT_FILE_TARGET` TARGET: path of the file in the storage<br>`GITS_EVENT_FILE_STORED` the file in the temporary clone, absolute path<br>`GITS_EVENT_FILE_ENCRYPTED` 1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET<br>`GITS_EVENT_FILE_INDEX` position of the element in GITS_LIST, from 1 |
| `GITS_PULL_BEFORE_COMPARE` | all local files are in the clone, 'git status' which decides "in sync or not" is next **can stop the command** | once (state: once per project) | — | — |
| `GITS_PULL_AFTER_COMPARE` | it is known whether the local files and the storage are in sync | once (state: once per project) | `$3` result | `GITS_EVENT_RESULT` insync, differs, or missing (a local file of the list doesn't exist)<br>`GITS_EVENT_CHANGED` local files which differ from the storage, absolute paths, one per line |
| `GITS_PULL_BEFORE_CLEANUP` | the temporary directory is about to be removed: the last moment to look into it **can stop the command** | once | `$3` temporary directory | — |
| `GITS_PULL_AFTER_CLEANUP` | the temporary directory is removed | once | `$3` temporary directory | — |
| `GITS_PULL_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_PULL_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits url`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_URL_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_URL_CONFIG_LOADED` | .git/gits.sh was executed: GITS_TARGETDIR and the list are known. From here on the scripts defined in the config run too | once (state: once per project) | — | — |
| `GITS_URL_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_URL_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits move`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_MOVE_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_MOVE_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_MOVE_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits migrate`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_MIGRATE_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_MIGRATE_FIND` | the projects below the current directory have to be found. The script does it: it prints the path of every config (.git/gits.sh, .git/gitstorage-config.sh), one per line. Default: events/defaults/FIND.sh **replaces a default** | once | `$3` directory to search | — |
| `GITS_MIGRATE_FOUND` | the projects are found | once | `$3` number of projects | `GITS_EVENT_FOUND_COUNT` number of projects<br>`GITS_EVENT_FOUND` directories of the projects, relative to GITS_EVENT_PWD, one per line |
| `GITS_MIGRATE_BEFORE_RENAME` | migrate: .git/gitstorage-config.sh of one project is about to become .git/gits.sh **can stop the command** | once per project which is migrated | `$3` old config<br>`$4` new config | `GITS_EVENT_RENAME_FROM` the old config, absolute path<br>`GITS_EVENT_RENAME_TO` the new config, absolute path |
| `GITS_MIGRATE_AFTER_RENAME` | migrate: the new config is written, the old one is removed | once per project which is migrated | `$3` old config<br>`$4` new config | `GITS_EVENT_RENAME_FROM` the old config, absolute path<br>`GITS_EVENT_RENAME_TO` the new config, absolute path |
| `GITS_MIGRATE_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_MIGRATE_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

### Events of `gits --update`

| Variable | When | Fired | Arguments after `<EVENT> <command>` | Own env vars |
|---|---|---|---|---|
| `GITS_UPDATE_START` | the arguments are read, nothing else happened yet **can stop the command** | once | — | — |
| `GITS_UPDATE_BEFORE_DOWNLOAD` | --update: the release to install is known, the download is next **can stop the command** | once, only when there is something to install | `$3` tag of the release | `GITS_EVENT_UPDATE_TAG` tag of the release which is installed<br>`GITS_EVENT_UPDATE_INSTALLED` the file which is replaced |
| `GITS_UPDATE_AFTER_DOWNLOAD` | --update: the new binary is downloaded next to the installed one, checked and tested | once, only when there is something to install | `$3` tag of the release | `GITS_EVENT_UPDATE_TAG` tag of the release which is installed<br>`GITS_EVENT_UPDATE_INSTALLED` the file which is replaced |
| `GITS_UPDATE_BEFORE_REPLACE` | --update: the installed binary is about to be replaced **can stop the command** | once, only when there is something to install | `$3` tag of the release | `GITS_EVENT_UPDATE_TAG` tag of the release which is installed<br>`GITS_EVENT_UPDATE_INSTALLED` the file which is replaced |
| `GITS_UPDATE_AFTER_REPLACE` | --update: the installed binary is the new one and it works | once, only when there is something to install | `$3` tag of the release | `GITS_EVENT_UPDATE_TAG` tag of the release which is installed<br>`GITS_EVENT_UPDATE_INSTALLED` the file which is replaced |
| `GITS_UPDATE_ERROR` | the command failed, its error message was just printed | once, only when the command fails | `$3` error message | `GITS_EVENT_ERROR` the error message |
| `GITS_UPDATE_END` | the last thing before gits exits, always: also after an error and after Ctrl+C | once | `$3` exit code | `GITS_EVENT_EXIT_CODE` the exit code gits ends with (130 after Ctrl+C) |

## Where to look next

| | |
|---|---|
| `gits events` | the list of events with what is defined on your machine right now |
| [events/examples/](events/examples/) | one script per variable (133), each with its whole context documented at the top and a body which works as it is. Written by `gits events --examples <directory>` |
| [events/defaults/](events/defaults/) | the default scripts of the replaceable events |
| [tests/test012/test.sh](tests/test012/test.sh) | registers every variable and dumps what each script sees. After `/bin/bash tests/test012/test.sh` the dumps are in `tests/test012/tmp/dumps/`, one directory per gits command, one file per call |
| [tests/test013/test.sh](tests/test013/test.sh) | stopping a command, scripts from the config, replacing `FIND`, no recursion |
| [IMPLEMENT_EVENTS.md](IMPLEMENT_EVENTS.md) | the requirements this was built from, and the decisions |
