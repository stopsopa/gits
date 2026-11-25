# gits

Keeps the files which don't belong to the repository of a project (`.env`, local configs,
editor settings, dotfiles from the home directory) in **one private git repository, the storage**.
Every project owns one directory there.

Rust rewrite of `gitstorage.sh`
([what the original does](REVERSE_PLAN.md), [the idea in the owner's words](PLAN.md), [what changed](CHANGES.md)).

This page goes from the simplest use to the more involved ones. Every step here can be tried
by hand, command by command, in a throwaway directory: [examples/SUMMARY.md](examples/SUMMARY.md).

1. [Install](#1-install)
2. [The first project](#2-the-first-project)
3. [Every day: diff and push](#3-every-day-diff-and-push)
4. [Another machine: init and pull](#4-another-machine-init-and-pull)
5. [Adding files to the list](#5-adding-files-to-the-list)
6. [Many projects at once: state](#6-many-projects-at-once-state)
7. [The config is a shell script](#7-the-config-is-a-shell-script)
8. [Your own scripts between the stages: lifecycle events](#8-lifecycle-events)
9. [Encrypted files](#9-encrypted-files)
10. [Coming from gitstorage.sh, and the old names of the variables](#10-coming-from-gitstoragesh)
11. Reference: [commands](#commands), [environment variables](#environment-variables), [update](#update), [development](#development)

## 1. Install

Download the binary of your platform from [releases](https://github.com/stopsopa/gits/releases)
(`gits-darwin-arm64`, `gits-linux-x64`, `gits-linux-arm64`), or build it: `/bin/bash compile.sh`
gives `bin/<arch>/gits`.

```sh
mkdir -p ~/.gits
curl -fsSL "https://github.com/stopsopa/gits/releases/latest/download/gits-darwin-arm64" -o ~/.gits/gits
chmod +x ~/.gits/gits

# ~/.zshrc or ~/.bashrc
export PATH="${HOME}/.gits:${PATH}"
export GITS_SOURCE="git@github.com:<owner>/<storage repository>.git"
```

`GITS_SOURCE` is the storage: a private git repository of yours, empty at the beginning. It is
the only thing gits needs to know. Later: `gits --update`.

Needs `git`. `curl` or `wget` only for `gits --update` and for `gits init` with a template given as url.

## 2. The first project

In the root of a project (a git repository with a remote `origin`):

```sh
gits init          # creates .git/gits.sh
```

`.git/gits.sh` is the config of the project. It is inside `.git`, so it is never committed
with the project. It defines two things:

```bash
GITS_TARGETDIR="git@github.com:stopsopa__gits.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"       # "SOURCE::TARGET"
    "../.env::$GITS_TARGETDIR/.env"
    "~/.zshrc::$GITS_TARGETDIR/.zshrc"
)
```

| | |
| --- | --- |
| `GITS_TARGETDIR` | directory of this project in the storage. `gits init` makes it from the url of the remote `origin`, with every `/` replaced by `__` |
| SOURCE | file on this machine: absolute path, path starting with `~/`, or path relative to the directory of the config (`.git`): `../.env` is `.env` in the root of the project |
| TARGET | path in the storage, inside a directory, without `..` |

The first element stores the config itself: keep it, it is what lets another machine get the
list back. Then:

```sh
gits diff          # what would be stored: everything, the storage has nothing yet
gits push --yes    # local files -> storage
```

Everything which needs the storage clones it to a directory with a random name in the current
directory and removes it at the end, also after an error or Ctrl+C.

## 3. Every day: diff and push

```sh
gits diff          # git diff + git status: "-" is what is stored, "+" what is here
gits push --yes    # store it. Without --yes nothing is changed, gits only says whether there is something to push
gits isinsync      # no output, only the exit code: 0 in sync, 1 not in sync, 2 error
```

`gits diff` ends with the list of the local files which differ, with absolute paths (in the
terminal of an editor a path can be clicked), and the address of the project in the storage.

## 4. Another machine: init and pull

Clone the project, then:

```sh
gits init          # the storage has a config for this remote: it is restored
gits pull --yes    # storage -> local files, THEY ARE OVERWRITTEN
```

`pull` takes the stored config first: when the list changed on the other machine, the new list
is used in the same run.

## 5. Adding files to the list

```sh
gits add .env config/          # a file, or every file of a directory
gits add ~/.zshrc              # a file from home is written as ~/...
```

In a terminal `add` shows first what it found, one row per file which is not in the list yet:

```
  gits add: 3 found, 2 ticked, 1 encrypted   (1 already in the config)

    add enc  file
    [x] [ ]  .env
  > [x] [x]  config/secret.json
    [ ]      config/public.json
```

| key | |
| --- | --- |
| arrows (or `h` `j` `k` `l`) | up / down between the files, left / right between the two boxes |
| `space` | tick or untick the box under the cursor |
| `a` `n` `i` | column **add**: all, none, invert |
| `A` `N` `I` | column **enc**, among the ticked rows: all, none, invert |
| `ctrl+enter` | write the ticked files to the config |
| `q` `esc` `ctrl+c` | leave, nothing is written |

- **add**: the file goes to the list. Everything is ticked at the beginning.
- **enc**: the file is written as an [encrypted element](#9-encrypted-files) (`SOURCE:e:TARGET`).
  The box exists only in a ticked row. `gits add -e` starts with all of them ticked.
- Enter alone never writes. A terminal which can't tell `ctrl+enter` from Enter (Terminal.app
  of macOS, some terminals of editors): `ctrl+j` or `ctrl+s` do the same.
- `gits add --yes ...`, or `add` without a terminal (in a script, in a pipe): no list, every
  found file is added.

`add` only appends lines to `GITS_LIST`, in the style the config already uses. Nothing is
copied or pushed, so the result can be reviewed: `gits diff`, then `gits push --yes`.

## 6. Many projects at once: state

In a directory with many projects (`~/Workspace`):

```sh
gits state         # every project below the current directory: in sync or not
gits find          # only the list of them
```

For every project `state` prints `cd "<project>"` and `gits diff`, ready to paste into another
terminal. Exit code 1 when anything is not in sync.

A project is a directory with `.git/gits.sh`. `node_modules` is not entered, symlinks are not
followed. The search itself is a script you can replace: see [lifecycle events](#8-lifecycle-events).

## 7. The config is a shell script

`.git/gits.sh` is executed by the shell from `GITS_SHELL` (default `/bin/bash`) from the root
of the project, and gits reads the two variables afterwards. So the list can be computed, and
whatever the config prints is shown:

```bash
GITS_TARGETDIR="git@github.com:stopsopa__gits.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
)

for FILE in .env*; do
    GITS_LIST+=("../$FILE::$GITS_TARGETDIR/$FILE")
done
```

`gits init` on a project the storage doesn't know yet uses a built-in template, or yours:
`GITS_TEMPLATE` is a file or a url; its line `GITS_TARGETDIR=...` is replaced.

## 8. Lifecycle events

Every command is a chain of stages (read the config, clone, copy, compare, commit, push, clean
up). Between the stages gits runs your scripts. The name of the variable says when, its value
is the path of the script:

```sh
export GITS_PUSH_AFTER_PUSH="~/.gits/events/after-push.sh"     # after "gits push --yes" pushed
export GITS_PUSH_BEFORE_PUSH="~/.gits/events/check.sh"         # a non-zero exit code refuses the push
export GITS_ALL="~/.gits/events/log.sh"                        # every event of every command
```

- The script is executed by the shell from `GITS_SHELL` and gets everything gits knows at that
  moment as `GITS_EVENT_*` env vars: which event it is, the directory, the temporary clone, the
  file being copied, the result, the commit.
- `START` and `BEFORE_*` scripts can stop the command; a failing `AFTER_*` script is only a warning.
- The same variables can be defined in `.git/gits.sh`: a project carries its own scripts.
- Some stages are scripts themselves and can be replaced, e.g. the search of `gits state`
  (`GITS_STATE_FIND`, default [events/defaults/FIND.sh](events/defaults/FIND.sh)).

```sh
gits events                              # every event of every command, and which ones are defined now
gits events --examples <directory>       # an example script of every event, its context documented at the top
```

**Everything about them, with a graph of every command: [LIFECYCLE.md](LIFECYCLE.md).**
Example scripts: [events/examples/](events/examples/).

## 9. Encrypted files

An element written `SOURCE:e:TARGET` is stored encrypted. gits doesn't encrypt and starts no
program for it: it connects to the unix socket from `GITS_ENCRYPTION_SOCKET` and sends

```
encode "<plain file>" "<encrypted file>"
decode "<encrypted file>" "<plain file>"
```

to the process listening there, which is the encoder of
[submodules/encrypt](submodules/encrypt/examples/SUMMARY.md) (`examples/socket/server.ts`, chapter
`socket-002-encoder_process_on_a_socket`). The key never passes through gits.

- `diff`, `isinsync`, `state`: the stored files are decrypted inside the temporary clone, so the diff is in plain text.
- `push --yes`: the stored file is decrypted and compared first; when nothing was edited it is left
  byte for byte as it is. Otherwise SOURCE is copied next to TARGET under a name which doesn't exist
  (`TARGET.hash<random>`), encrypted over the existing TARGET (so only the edited lines change in the
  stored file) and the copy is removed.
- `pull --yes`: decrypted next to the stored file, then copied over SOURCE. A failed decryption never touches the local file.
  The config is pulled first: when the stored one differs from the local one the list is read again before any
  other file is copied, so a file another machine marked `:e:` is never copied over the local one encrypted.
- An element changed from `::` to `:e:` (or back) is converted by the next `gits push --yes`.

### Keeping the encoder process running

The encoder process needs Node.js >= 22.18, a checkout of
[stopsopa/encrypt](https://github.com/stopsopa/encrypt) (here: `submodules/encrypt`) and an ssh key
whose private part is loaded in your `ssh-agent` (`ssh-add -l`).

```sh
export GITS_ENCRYPTION_SOCKET="${HOME}/.gits/ssenc.sock"   # where it listens, gits reads the same variable
export GITS_ENCODER_SSH_KEY="${HOME}/.ssh/id_ed25519.pub"       # .pub file or fingerprint (SHA256:...)

/bin/bash tests/encoder/encoder-start.sh     # starts it; when it already runs nothing happens. Call it as often as you like
gits diff
/bin/bash tests/encoder/encoder-stop.sh      # stops it; fine to call when it doesn't run
```

It keeps running after the terminal is closed. Next to the socket are `<socket>.pid` and
`<socket>.log` (one line per request). `GITS_ENCODER_DIR` points to the checkout of
stopsopa/encrypt when it is not `submodules/encrypt` of this repository.

### The wrapper: `gits.sh`

`gits.sh` calls `tests/encoder/encoder-start.sh` and then the binary with the same arguments, so the
encoder process doesn't have to be thought about:

```sh
export GITS_SOURCE="git@github.com:you/storage.git"
export GITS_BIN="/path/to/gits"                          # the binary
export GITS_ENCODER_SSH_KEY="~/.ssh/id_ed25519.pub"
alias gits='/bin/bash "/path/to/this/repository/gits.sh"'
```

- Without `GITS_ENCODER_SSH_KEY` nothing is started, the binary is called as it is.
- Without `GITS_ENCRYPTION_SOCKET` the socket is `~/.gits/ssenc.sock`.
- Nothing is printed about the encoder process unless it can't be started; then gits is not
  called and the exit code is 1.
- It works from a checkout of this repository (it finds `tests/encoder/encoder-start.sh` relative to itself).
  It is not part of a release and `gits --update` replaces only the binary.

## 10. Coming from gitstorage.sh

**The config.** The old tool kept it in `.git/gitstorage-config.sh`. gits finds such projects
and migrates them: the file becomes `.git/gits.sh`, the element which stores the config itself
gets the new name, and the two variables are renamed. Nothing else in the file is touched.

```sh
gits migrate          # in the root of a project
gits migrate all      # every project below the current directory
```

Any command which finds only the old config migrates it first. The old
`gitstorage-config.sh` stays in the storage until you remove it there by hand.

**The names of the variables.** Everything used to start with `GITSTORAGE`; now it is `GITS_`.
The old names are still read when the new one is not defined, so nothing breaks on the day of
the update; `gits --help` shows where a value came from.

| Old | New | Where |
| --- | --- | --- |
| `GITSTORAGESOURCE` | `GITS_SOURCE` | environment |
| `GITSTORAGETESHELL` | `GITS_SHELL` | environment |
| `GITSTORAGETENCRYPTIONSOCKET` | `GITS_ENCRYPTION_SOCKET` | environment |
| `GITSTORAGETEMPLATE` | `GITS_TEMPLATE` | environment |
| `GITSTORAGETARGETDIR` | `GITS_TARGETDIR` | `.git/gits.sh` |
| `GITSTORAGELIST` | `GITS_LIST` | `.git/gits.sh` |

A config with the old two names works as it is. `gits migrate` in a project which already has
`.git/gits.sh` renames them in the file.

## Commands

In any directory:

| | |
| --- | --- |
| `gits state` | finds all projects below the current directory and says for each whether it is in sync. For each it prints `cd "<project>"` and `gits diff`, ready to paste. Exit code 1 when anything is not in sync |
| `gits find` | only lists the directories of those projects, one per line (`.` or `./path`) |
| `gits migrate all` | `.git/gitstorage-config.sh` -> `.git/gits.sh` in all of them |
| `gits events` | every lifecycle event of every command and which ones have a script now. `gits events --examples <directory>` writes an example script of each |

In the root of a project:

| | |
| --- | --- |
| `gits init` | creates `.git/gits.sh`: the one from the storage when the project was set up on another machine, else from the template (`GITS_TEMPLATE`, else built-in) |
| `gits diff` | copies every SOURCE over TARGET in the clone and shows `git diff` + `git status`: `-` is what is stored, `+` what is here. Then the list of local files which differ, with absolute paths (clickable in the terminal of an editor), and the url of the project in the storage. Exit code 0 in sync, 1 not |
| `gits isinsync` | the same check, no output: exit code 0 in sync, 1 not in sync, 2 error |
| `gits push --yes` | local files -> storage: commit `gits push <GITS_TARGETDIR>` and push. Without `--yes` nothing is changed |
| `gits pull --yes` | storage -> local files, **they are overwritten**. Without `--yes` nothing is changed |
| `gits url` | web address of the directory of the project in the storage |
| `gits add [-e] [--yes] <file\|directory> ...` | appends elements to `GITS_LIST`, nothing else, so it can be reviewed. In a terminal: [a list to tick](#5-adding-files-to-the-list) which files and which of them encrypted, written after `ctrl+enter`. `-e`: encrypted from the start. `--yes`: no list, everything found |
| `gits move <old remote> <new remote>` | prints the procedure of renaming the directory in the storage after the remote `origin` changed |
| `gits migrate` | `.git/gitstorage-config.sh` -> `.git/gits.sh`, old names of the variables -> new ones |

## Environment variables

`gits --help` prints this table with the values found on your machine.

| Variable | Default | |
| --- | --- | --- |
| `GITS_SOURCE` | required | the storage, e.g. `git@github.com:stopsopa/gitstorage.git`. Checked before anything else; only `--help`, `--version`, `events` and `--update` work without it |
| `GITS_SHELL` | `/bin/bash` | shell which executes `.git/gits.sh` and the lifecycle scripts |
| `GITS_ENCRYPTION_SOCKET` | | unix socket of the encoder process, needed only for `:e:` elements |
| `GITS_TEMPLATE` | built-in | url or file: template for `gits init`. Its line `GITS_TARGETDIR=...` is replaced |
| `GITS_<COMMAND>_<EVENT>`, `GITS_<COMMAND>_ALL`, `GITS_ALL` | | path of a lifecycle script, see [LIFECYCLE.md](LIFECYCLE.md) and `gits events` |
| `GITS_RELEASES` | `https://github.com/stopsopa/gits/releases` | where `gits --update` takes releases from (url or directory) |
| `GITS_CONFIRM` | `true` | `false`: `gits --update` doesn't ask |

## Update

```
gits --update            update to the latest release
gits --update <tag>      install the given release (also an older one), e.g. v0.1.0
gits --update --check    only say whether there is something newer, change nothing
```

Implemented the way [submodules/xx/UPDATE_IMPLEMENTATION.md](submodules/xx/UPDATE_IMPLEMENTATION.md)
describes: the new binary is downloaded next to the installed one, its sha256 is compared with
`SHA256SUMS.txt` of the release, it is executed and has to report the expected version, and only
then the installed file is replaced (by rename). After any failure the installed file is what it was.
The checksum comes from the same release, so it protects against a broken download, not against
somebody who controls the release.

## Development

```sh
/bin/bash compile.sh                  # bin/<arch>/gits, version "dev"
/bin/bash test.sh                     # cargo test + every tests/testNNN/test.sh, exit code 1 when anything fails
/bin/bash tests/test003/test.sh       # only this one
/bin/bash tag.sh patch                # next tag, pushed: the workflow builds and publishes the release
```

Every `tests/testNNN/test.sh` is a list of checks made with the function `test` of the library
`bash/test.sh`: a command (`COMMAND`) and what it has to give (`EXPECTED_STDOUT`, `EXPECTED_STDERR`,
`EXPECTED_CODE`). A single test can be executed alone: `/bin/bash tests/test003/test.sh`.
Every test works in `tests/testNNN/tmp/` with its own `HOME`, git config and an empty
repository as the storage (`tests/_lib.sh`, also the helpers used in the commands). That directory is
ignored by git (`tests/testNNN/.gitignore`), cleared at the beginning of the test and left there at its
end, to look at what the test produced.
`tests/test007` (encryption) uses the real encoder process of `submodules/encrypt`
(`examples/socket/server.ts`, with a demo ssh key in a private `ssh-agent` and `--seal`) and the `ssenc`
binary of the submodule to check the stored files from outside; the binary is compiled by the test when
it is not there yet. The submodule has to be there: `git submodule update --init submodules/encrypt`.
`tests/test012` registers a script for every lifecycle event and leaves what each of them saw in
`tests/test012/tmp/dumps/`.

| | |
| --- | --- |
| `src/main.rs` | arguments, `--help` |
| `src/config.rs` | reading `.git/gits.sh`, migration, finding projects |
| `src/ops.rs` | the temporary clone, `diff`, `isinsync`, `push`, `pull`, `state`, `url` |
| `src/commands.rs` | `init`, `add`, `find`, `migrate`, `move` |
| `src/events.rs` | lifecycle events: the list of events, running the scripts, `gits events`, the example scripts |
| `events/defaults/` | default scripts of the replaceable events, compiled into the binary |
| `events/examples/` | an example script per event, generated: `gits events --examples events/examples` (a test checks that it is up to date) |
| `src/cli.rs` | the only place where other programs are started (git, the shell reading the config, curl...): env, working directory, output forwarded while it flows and collected. Rust version of `workshop/cli/cli.ts` |
| `src/socket.rs` | client of the encoder process |
| `src/update.rs` | `--update` |
| `gits.sh` | wrapper: makes sure the encoder process runs, then calls the binary |
| `tests/encoder/encoder-start.sh`, `tests/encoder/encoder-stop.sh` | the encoder process of `submodules/encrypt` on `GITS_ENCRYPTION_SOCKET` |
| `.github/workflows/rust.yml` | test -> build (macOS arm64, Linux x64, Linux arm64) -> release on a tag |
