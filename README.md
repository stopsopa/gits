# gits

Keeps the files which don't belong to the repository of a project (`.env`, local configs,
editor settings, dotfiles from the home directory) in **one private git repository, the storage**.
Every project owns one directory there.

Rust rewrite of `gitstorage.sh`
([what the original does](REVERSE_PLAN.md), [the idea in the owner's words](PLAN.md), [what changed](CHANGES.md)).

## Install

Download the binary of your platform from [releases](https://github.com/stopsopa/gits/releases)
(`gits-darwin-arm64`, `gits-linux-x64`, `gits-linux-arm64`), or build it: `/bin/bash compile.sh`
gives `bin/<arch>/gits`.

```sh
mkdir -p ~/.gits
curl -fsSL "https://github.com/stopsopa/gits/releases/latest/download/gits-darwin-arm64" -o ~/.gits/gits
chmod +x ~/.gits/gits

# ~/.zshrc or ~/.bashrc
export PATH="${HOME}/.gits:${PATH}"
export GITSTORAGESOURCE="git@github.com:<owner>/<storage repository>.git"
```

Later: `gits --update`.

Needs `git`. `curl` or `wget` only for `gits --update` and for `gits init` with a template given as url.

## The config: `.git/gits.sh`

Inside `.git`, so it is never committed with the project. It is a shell script which defines two things:

```bash
GITSTORAGETARGETDIR="git@github.com:stopsopa__gits.git"

GITSTORAGELIST=(
    "gits.sh::$GITSTORAGETARGETDIR/gits.sh"       # "SOURCE::TARGET"    stored as it is
    "../.env:e:$GITSTORAGETARGETDIR/.env"         # "SOURCE:e:TARGET"   stored encrypted
    "~/.zshrc::$GITSTORAGETARGETDIR/.zshrc"
)
```

| | |
| --- | --- |
| `GITSTORAGETARGETDIR` | directory of this project in the storage. `gits init` makes it from the url of the remote `origin`, with every `/` replaced by `__` |
| SOURCE | file on this machine: absolute path, path starting with `~/`, or path relative to the directory of the config (`.git`): `../.env` is `.env` in the root of the project |
| TARGET | path in the storage, inside a directory, without `..` |

The config is executed by the shell from `GITSTORAGETESHELL` (default `/bin/bash`) from the root
of the project, so it can compute elements (`GITSTORAGELIST+=(...)` under a condition) and print
messages; whatever it prints is shown.

## Commands

Everything which needs the storage clones it to a directory with a random name in the current
directory and removes it at the end, also after an error or Ctrl+C.

In any directory:

| | |
| --- | --- |
| `gits state` | finds all projects below the current directory and says for each whether it is in sync. For each it prints `cd "<project>"` and `gits diff`, ready to paste. Exit code 1 when anything is not in sync |
| `gits find` | only lists the directories of those projects, one per line (`.` or `./path`) |
| `gits migrate all` | `.git/gitstorage-config.sh` -> `.git/gits.sh` in all of them |

A project is a directory with `.git/gits.sh` or `.git/gitstorage-config.sh`. `node_modules` and
`.git` directories are not entered, symlinks to directories are not followed.

In the root of a project:

| | |
| --- | --- |
| `gits init` | creates `.git/gits.sh`: the one from the storage when the project was set up on another machine, else from the template (`GITSTORAGETEMPLATE`, else built-in) |
| `gits diff` | copies every SOURCE over TARGET in the clone and shows `git diff` + `git status`: `-` is what is stored, `+` what is here. Then the list of local files which differ, with absolute paths (clickable in the terminal of an editor), and the url of the project in the storage. Exit code 0 in sync, 1 not |
| `gits isinsync` | the same check, no output: exit code 0 in sync, 1 not in sync, 2 error |
| `gits push --yes` | local files -> storage: commit `gits push <GITSTORAGETARGETDIR>` and push. Without `--yes` nothing is changed |
| `gits pull --yes` | storage -> local files, **they are overwritten**. Without `--yes` nothing is changed |
| `gits url` | web address of the directory of the project in the storage |
| `gits add [-e] <file\|directory> ...` | appends elements to `GITSTORAGELIST`, nothing else, so it can be reviewed. `-e`: as encrypted |
| `gits move <old remote> <new remote>` | prints the procedure of renaming the directory in the storage after the remote `origin` changed |
| `gits migrate` | `.git/gitstorage-config.sh` -> `.git/gits.sh`. Also done automatically by any command which finds only the old one |

A new machine: clone the project, `gits init`, `gits pull --yes`.

## Encryption

An element written `SOURCE:e:TARGET` is stored encrypted. gits doesn't encrypt and starts no
program for it: it connects to the unix socket from `GITSTORAGETENCRYPTIONSOCKET` and sends

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
- An element changed from `::` to `:e:` (or back) is converted by the next `gits push --yes`.

### Keeping the encoder process running

The encoder process needs Node.js >= 22.18, a checkout of
[stopsopa/encrypt](https://github.com/stopsopa/encrypt) (here: `submodules/encrypt`) and an ssh key
whose private part is loaded in your `ssh-agent` (`ssh-add -l`).

```sh
export GITSTORAGETENCRYPTIONSOCKET="${HOME}/.gits/ssenc.sock"   # where it listens, gits reads the same variable
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
export GITSTORAGESOURCE="git@github.com:you/storage.git"
export GITS_BIN="/path/to/gits"                          # the binary
export GITS_ENCODER_SSH_KEY="~/.ssh/id_ed25519.pub"
alias gits='/bin/bash "/path/to/this/repository/gits.sh"'
```

- Without `GITS_ENCODER_SSH_KEY` nothing is started, the binary is called as it is.
- Without `GITSTORAGETENCRYPTIONSOCKET` the socket is `~/.gits/ssenc.sock`.
- Nothing is printed about the encoder process unless it can't be started; then gits is not
  called and the exit code is 1.
- It works from a checkout of this repository (it finds `tests/encoder/encoder-start.sh` relative to itself).
  It is not part of a release and `gits --update` replaces only the binary.

## Environment variables

`gits --help` prints this table with the values found on your machine.

| Variable | Default | |
| --- | --- | --- |
| `GITSTORAGESOURCE` | required | the storage, e.g. `git@github.com:stopsopa/gitstorage.git`. Checked before anything else; only `--help`, `--version` and `--update` work without it |
| `GITSTORAGETESHELL` | `/bin/bash` | shell which executes `.git/gits.sh` |
| `GITSTORAGETENCRYPTIONSOCKET` | | unix socket of the encoder process, needed only for `:e:` elements |
| `GITSTORAGETEMPLATE` | built-in | url or file: template for `gits init`. Its line `GITSTORAGETARGETDIR=...` is replaced |
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

| | |
| --- | --- |
| `src/main.rs` | arguments, `--help` |
| `src/config.rs` | reading `.git/gits.sh`, migration, finding projects |
| `src/ops.rs` | the temporary clone, `diff`, `isinsync`, `push`, `pull`, `state`, `url` |
| `src/commands.rs` | `init`, `add`, `find`, `migrate`, `move` |
| `src/cli.rs` | the only place where other programs are started (git, the shell reading the config, curl...): env, working directory, output forwarded while it flows and collected. Rust version of `workshop/cli/cli.ts` |
| `src/socket.rs` | client of the encoder process |
| `src/update.rs` | `--update` |
| `gits.sh` | wrapper: makes sure the encoder process runs, then calls the binary |
| `tests/encoder/encoder-start.sh`, `tests/encoder/encoder-stop.sh` | the encoder process of `submodules/encrypt` on `GITSTORAGETENCRYPTIONSOCKET` |
| `.github/workflows/rust.yml` | test -> build (macOS arm64, Linux x64, Linux arm64) -> release on a tag |
