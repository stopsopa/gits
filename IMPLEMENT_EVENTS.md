# Lifecycle events: requirements

Status: **not implemented yet.** This file collects what was asked for, refined, plus the
proposals and open questions which have to be answered before the implementation starts
(chapter [Open questions](#open-questions)).

## What was asked for

1. Every gits command has stages (clone, decrypt, copy, diff, encrypt, commit, push, ...).
   Between the stages gits runs **lifecycle scripts** defined in env vars:

   ```
   GITSTORAGE_STATE_<EVENT NAME>
   GITSTORAGE_DIFF_<EVENT NAME>
   GITSTORAGE_PULL_<EVENT NAME>
   GITSTORAGE_PUSH_<EVENT NAME>
   ... and so on, for each command
   ```

2. The scripts are executed by the shell from `GITSTORAGETESHELL` (default `/bin/bash`), the
   same shell which runs `.git/gits.sh`.

3. Every script gets **everything gits knows at that moment**, as env vars and arguments
   ("assume everything what moves is useful"):
   - all native env vars of `ENVVARS.md`: `GITSTORAGESOURCE`, `GITSTORAGETARGETDIR`,
     `GITSTORAGETEMPLATE`, `GITSTORAGETESHELL`, `GITSTORAGETENCRYPTIONSOCKET`
   - the current event
   - the directory where the gits command was called
   - the path of the temporary directory (the clone of the storage)
   - the name of the repository, and whatever else is at hand

4. A script has to be able to know **which event it is**, also when one command fires the
   same kind of event more than once (`before encrypt` / `after encrypt` for every file):
   such events are numbered.

5. `LIFECYCLE.md`: documentation for each command (`gits state`, `gits diff`, `gits pull`, ...)
   describing in stages what happens after what, with ascii graphs with arrows, and for every
   event: its env var name, and which env vars and arguments are injected into it.

6. New test cases: every event env var is registered, each script dumps everything it sees,
   and (as in the other tests) the dumps stay in `tests/testNNN/tmp/` after the test to look at.

7. This file: the requirements above, refined.

## Proposal

### How a script is defined and run

- The value of the env var is a **command line**, run as `$GITSTORAGETESHELL -c "<value>"`.
  So it can be a path to a script or anything inline:

  ```sh
  export GITSTORAGE_PUSH_AFTER_PUSH='/bin/bash ~/.gits/hooks/after-push.sh'
  export GITSTORAGE_DIFF_END='echo "diff ended with $GITS_EVENT_EXIT_CODE"'
  ```

- An event whose env var is not defined (or empty) costs nothing: no process is started.
- Working directory of the script: the root of the project (for `state`: the directory where
  `gits state` was called, and the project being checked is in an env var).
- stdout and stderr of the script are shown as they come. In `gits isinsync` (which must print
  nothing on stdout) stdout of the script goes to stderr.
- The script is started through `src/cli.rs`, like every other program.

### Names of the events

`GITSTORAGE_<COMMAND>_<EVENT>`, where `<COMMAND>` is one of `STATE FIND INIT ADD DIFF ISINSYNC
PUSH PULL URL MOVE MIGRATE UPDATE`.

Events which every command has:

| Event | When |
|---|---|
| `START` | arguments are read, nothing else happened |
| `END` | the last thing before gits exits, always (also after an error or Ctrl+C). The exit code is known |
| `ERROR` | an error is about to be reported. The message is known |

Events of the commands which use the storage (`DIFF ISINSYNC PUSH PULL`, and `STATE` per project):

| Event | When | Fired |
|---|---|---|
| `CONFIG_LOADED` | `.git/gits.sh` was executed, the list is known | once |
| `BEFORE_CLONE` / `AFTER_CLONE` | around `git clone` of the storage into the temporary directory | once |
| `BEFORE_DECRYPT` / `AFTER_DECRYPT` | around the decryption of one stored `:e:` file | per encrypted file |
| `BEFORE_COPY` / `AFTER_COPY` | around the copy of one file (SOURCE -> clone, or clone -> SOURCE for `pull`) | per file |
| `BEFORE_COMPARE` / `AFTER_COMPARE` | around `git status` which decides "in sync or not". After: the result and the changed files are known | once |
| `BEFORE_ENCRYPT` / `AFTER_ENCRYPT` | `push`: around the encryption of one file (the plain copy `TARGET.hash…` exists) | per encrypted file |
| `BEFORE_COMMIT` / `AFTER_COMMIT` | `push`: around `git commit` in the clone | once |
| `BEFORE_PUSH` / `AFTER_PUSH` | `push`: around `git push` to the storage | once |
| `BEFORE_CLEANUP` / `AFTER_CLEANUP` | around the removal of the temporary directory | once |

`STATE` in addition: `FOUND` (the list of projects is known), `BEFORE_PROJECT` / `AFTER_PROJECT`
(per project, numbered, after: its result).
`INIT`: `BEFORE_WRITE` / `AFTER_WRITE` (the config, and where it came from: storage, template, built-in).
`ADD`: `BEFORE_WRITE` / `AFTER_WRITE` (the lines to add). `MIGRATE`: `BEFORE_RENAME` / `AFTER_RENAME`.
`UPDATE`: `BEFORE_DOWNLOAD` / `AFTER_DOWNLOAD`, `BEFORE_REPLACE` / `AFTER_REPLACE`.
`FIND`, `URL`, `MOVE`: only `START`, `END`, `ERROR`.

### What is injected

Env vars, always:

| Variable | Value |
|---|---|
| `GITSTORAGESOURCE`, `GITSTORAGETEMPLATE`, `GITSTORAGETESHELL`, `GITSTORAGETENCRYPTIONSOCKET` | as gits uses them (defaults applied) |
| `GITSTORAGETARGETDIR` | from the config, once it is loaded |
| `GITS_EVENT` | full name of the env var of this event, e.g. `GITSTORAGE_PUSH_BEFORE_ENCRYPT` |
| `GITS_EVENT_COMMAND` | `push` |
| `GITS_EVENT_NAME` | `BEFORE_ENCRYPT` |
| `GITS_EVENT_SEQ` | number of this event among all events of this run, from 1 (also counting the ones without a script) |
| `GITS_EVENT_INDEX` | which occurrence of this particular event it is in this run, from 1 (`BEFORE_ENCRYPT` of the 3rd file: `3`) |
| `GITS_EVENT_PWD` | directory where gits was called |
| `GITS_EVENT_ARGS` | the arguments gits was called with |
| `GITS_EVENT_BIN`, `GITS_EVENT_VERSION` | path of the gits binary, its version |
| `GITS_EVENT_PID` | pid of gits |

Once known:

| Variable | Value |
|---|---|
| `GITS_EVENT_PROJECT_DIR` | root of the project |
| `GITS_EVENT_CONFIG` | path of `.git/gits.sh` |
| `GITS_EVENT_REMOTE` | url of remote `origin` of the project |
| `GITS_EVENT_LIST_COUNT` | number of elements of `GITSTORAGELIST` |
| `GITS_EVENT_LIST_FILE` | path of a file with the whole list, one element per line: `encrypted<TAB>SOURCE<TAB>TARGET` |
| `GITS_EVENT_TEMP_DIR` | the temporary directory (clone of the storage) |
| `GITS_EVENT_STORAGE_DIR` | directory of the project inside the clone (`<temp>/<GITSTORAGETARGETDIR>`) |
| `GITS_EVENT_STORAGE_BRANCH` | branch of the storage |
| `GITS_EVENT_YES` | `1` when `--yes` was given |

Per file (`*_DECRYPT`, `*_COPY`, `*_ENCRYPT`):

| Variable | Value |
|---|---|
| `GITS_EVENT_FILE_SOURCE` | local file, absolute |
| `GITS_EVENT_FILE_SOURCE_RAW` | SOURCE as written in the config |
| `GITS_EVENT_FILE_TARGET` | TARGET, path in the storage |
| `GITS_EVENT_FILE_STORED` | the file in the clone, absolute |
| `GITS_EVENT_FILE_ENCRYPTED` | `1` for `:e:` |
| `GITS_EVENT_FILE_PLAIN` | the temporary plain copy (`TARGET.hash…`), while it exists |
| `GITS_EVENT_FILE_INDEX`, `GITS_EVENT_FILE_COUNT` | position in the list |

Results (in the `AFTER_*`, `END`, `ERROR` events where they exist):

| Variable | Value |
|---|---|
| `GITS_EVENT_EXIT_CODE` | exit code gits is about to end with (`END`) |
| `GITS_EVENT_ERROR` | the error message (`ERROR`) |
| `GITS_EVENT_RESULT` | `insync`, `differs` or `missing` (`AFTER_COMPARE`, `AFTER_PROJECT`, `END`) |
| `GITS_EVENT_CHANGED_FILE` | path of a file with the local files which differ, one per line |
| `GITS_EVENT_COMMIT` | hash of the new commit (`AFTER_COMMIT`, `AFTER_PUSH`) |
| `GITS_EVENT_STATE_INDEX`, `GITS_EVENT_STATE_COUNT`, `GITS_EVENT_COUNT_SUCCESS`, `GITS_EVENT_COUNT_ERROR` | `state` |

Arguments: `$1` the name of the event (`BEFORE_ENCRYPT`), `$2` the command (`push`); for the
per-file events `$3` SOURCE (absolute), `$4` the file in the clone.

### Tests

- `tests/test012`: one dump script, registered for every event of every command; each call
  writes one file `tests/test012/tmp/dumps/<SEQ>-<COMMAND>-<EVENT>-<INDEX>.txt` with its
  arguments, its working directory and all `GITS*` env vars. The checks: which events fired, in
  which order, with which values.
- a test for scripts which fail (see the open question about that), for `isinsync` staying
  silent, for `GITSTORAGETESHELL`.

## Open questions

Ideas which were not asked for, and decisions which change the design. Each has a
recommendation; say which ones you want.

1. **Can a script stop the command?** Recommended: yes for `BEFORE_*` and `START`: a non-zero
   exit code aborts the command (the temporary directory is still removed, `ERROR` and `END`
   still fire). A failing `AFTER_*` / `END` / `ERROR` script only prints a warning. This makes
   "check something before push, refuse the push" possible.

2. **A catch-all variable.** `GITSTORAGE_ALL` (every event of every command) and
   `GITSTORAGE_<COMMAND>_ALL` (every event of one command), run in addition to the specific
   one. Recommended: yes. It makes logging one line of config, and the dump test simple.

3. **Per-project scripts.** `.git/gits.sh` is a shell script already: gits could also read the
   `GITSTORAGE_<COMMAND>_<EVENT>` variables which the config sets, so a project can have its
   own scripts (stored with the config). The env var of the terminal and the one of the config
   would both run, env first. Recommended: yes, but it is extra work; can come second.
   Note: events before `CONFIG_LOADED` can only come from the env.

4. **The prefix of the injected variables.** Proposed above: `GITS_EVENT_*`, to keep them apart
   from the `GITSTORAGE_*` names which define scripts. Alternative: `GITSTORAGE_EVENT_*`.

5. **The value: a command line or a path?** Proposed above: a command line given to
   `$GITSTORAGETESHELL -c`. Alternative: only a path to a script file. A command line covers both.

6. **Nested gits.** A script may call gits itself (e.g. `gits isinsync` of another project).
   Recommended: the inner gits fires its own events, `GITS_EVENT_DEPTH` says how deep, and
   beyond depth 5 gits refuses to run scripts (protection from a script which calls itself).

7. **`gits events`.** A command which prints every event name per command and marks the ones
   defined right now (like the env table of `--help`). Recommended: yes, small.

8. **Events for every command, also `find`, `url`, `move`, `init`, `add`, `migrate`,
   `--update`?** You wrote "for each command". Proposed above: yes, most of them with only
   `START` / `END` / `ERROR`.

9. **Per-file events in `state`.** `gits state` over 100 projects with 10 files each fires
   thousands of per-file events. No cost when nothing is defined, but a defined
   `GITSTORAGE_STATE_BEFORE_COPY` is started for every file. Recommended: keep them, as asked.
