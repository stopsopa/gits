# REVERSE_PLAN: what the original `gitstorage.sh` does

Reverse engineered from `submodules/stopsopa.github.io/gitstorage.sh` and the files it uses
(`gitstorage-core.sh`, `gitstorage.cjs`, `gitstorage-config.sh`). It describes behaviour, not
implementation, the way it would be handed to somebody who has to write the tool from scratch.

`PLAN.md` is the owner's description of the same tool, `CHANGES.md` says what the new
implementation (`gits`, Rust) does differently. The last chapter here lists where the original
differs from those two, and what was decided.

## 1. The idea

Every project has files which must not be committed to the project's repository but are worth
keeping: `.env`, editor settings, local scripts, dotfiles from the home directory. `gitstorage.sh`
(alias `gits`) keeps them in **one private git repository, the storage**, shared by all projects.
Each project owns one directory in the storage.

The project describes its files in a config which lives inside `.git` (so it is never committed
and never shows in `git status`):

```bash
# .git/gitstorage-config.sh
GITSTORAGETARGETDIR="git@github.com:stopsopa__gitstorage.git"

GITSTORAGELIST=(
    "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"
    "../.env::$GITSTORAGETARGETDIR/.env"
    "~/.zshrc::$GITSTORAGETARGETDIR/.zshrc"
)
```

Nothing is kept between runs. Every command which needs the storage clones it into a directory
with a random name, does its work there and removes the directory when it ends, also after an
error or Ctrl+C.

## 2. Terms

| Term | Meaning |
|---|---|
| storage | the git repository from `GITSTORAGESOURCE`, e.g. `git@github.com:stopsopa/gitstorage.git` |
| project | a directory with `.git/gitstorage-config.sh`; commands are run from it |
| `GITSTORAGETARGETDIR` | name of the directory of this project inside the storage |
| `GITSTORAGELIST` | the list of files, one `SOURCE::TARGET` per element |
| SOURCE | a file on this machine |
| TARGET | path of its copy inside the storage (normally starts with `$GITSTORAGETARGETDIR/`) |

### How `GITSTORAGETARGETDIR` is made

From the url of the remote `origin` of the project, every `/` replaced with `__`:

```
git config --get remote.origin.url | sed -E 's/\//__/g'

git@github.com:stopsopa/gitstorage.git   ->   git@github.com:stopsopa__gitstorage.git
```

So the name is unique for a repository and is a valid single directory name. It is computed once,
by `init`, and written into the config. After that the config is the only source of it (that is
why `move` exists, chapter 4).

### How SOURCE is resolved

- starts with `/`: absolute path
- starts with `~/`: the home directory of the current user
- anything else: relative to the directory **of the config**, which is `.git`. So `xx.cjs` is
  `.git/xx.cjs` and `../.env` is `.env` in the root of the project.

Spaces in paths work. Only regular files are handled, a directory in the list is "missing".

### How an element is split

SOURCE is everything before the first `::`, TARGET everything after the last `::`.

### The config is a shell script

It is `source`d by bash with the root of the project as the current directory, so it can compute
things: detect a version of an installed program, add elements conditionally, print warnings.
Whatever it prints lands in the output of the command (that is the `all good IntelliJIdea2022.1`
line in `PLAN.md`). The example in `doc/gitstorage-config.sh` does exactly that.

## 3. Environment

| Variable | Meaning |
|---|---|
| `GITSTORAGESOURCE` | url of the storage. Required by everything which clones; may also be set inside the config |
| `REPO_DIR` | local clone of `stopsopa.github.io`; the script refuses to start without it (it links its own files from there) |

Programs it needs: `git`, `realpath` (coreutils), `openssl` (random directory name), `node` (only
`add`), `python`, `wget` or `curl` (only `init`).

## 4. Commands

`--yes` can be given with any command, it matters for `push` and `pull`.
Without arguments or with `--help` the list of commands is printed.

### The temporary clone (used by `isinsync`, `diff`, `push`, `pull`, `state`)

1. Pick a name: 4 random hex characters (`openssl rand -hex 2`), as a directory **in the current
   directory**. If it exists, pick another one.
2. Print `_TARGETGITDIR: <absolute path>`.
3. Register the cleanup (bash `trap ... EXIT`): print `gitstorage.sh cleaning <path>` and remove
   the directory. It runs however the command ends.
4. Create the directory and `git clone "$GITSTORAGESOURCE" .` inside it.

### `gits diff`

The command used every day: what changed locally since the last push?

1. Load the config (`.git/gitstorage-config.sh` in the current directory; error when missing or
   when `GITSTORAGELIST` is empty).
2. Make the temporary clone.
3. For every element copy SOURCE over TARGET inside the clone, creating directories. A SOURCE which
   doesn't exist prints an error; after the loop the command stops with
   `files are not in sync - at least one source file is missing`, exit code 1.
4. `git status -s` in the clone. Empty: `files are in sync`, exit code 0.
5. Otherwise: `files are not in sync`, then `git diff` and `git status` run inside
   `<clone>/$GITSTORAGETARGETDIR`, exit code 1.
6. In every case the last line is `final url <url>` (see `url`), then the cleanup.

The diff therefore reads "storage -> this machine": `-` lines are what is stored, `+` lines what is
here. Files which are new for the storage are untracked in the clone, so they show only in
`git status`, not in `git diff`.

### `gits isinsync`

The same steps as `diff` up to `git status -s`; meant to give an exit code: 0 in sync, 1 not.
(The original has a bug here: the result of `git status -s` is printed but never stored, so it
always reports "in sync" and exits 0. A missing SOURCE is only printed.)

### `gits push --yes`

Stores the local state.

1. Without `--yes`: run `isinsync` and stop. In sync: exit 0. Not in sync: error
   `files are not in sync, if you sure that you want to push them add --yes param`, exit 1.
   `--yes` exists so `gits push` can't be confused with a destructive `git push --force` habit:
   nothing happens without it.
2. Every TARGET has to be inside a directory (`xxx/file`, not `file`), otherwise error: a project
   may not write to the root of the storage.
3. Temporary clone, copy every SOURCE over TARGET, printing `'SOURCE' -> 'TARGET'`. A missing
   SOURCE prints an error and is skipped, the rest is still pushed.
4. Nothing changed (`git status -s` empty): `files are in sync`, exit 0.
5. Otherwise `git add .`, `git commit` with an empty message, `git push origin master`,
   `files pushed`, `final url <url>`.

### `gits pull --yes`

The opposite direction: storage -> this machine.

1. Without `--yes`: run `isinsync`, print `run with --yes to actually do pull`, stop (exit 0 in
   sync, 1 not).
2. Temporary clone. For every element copy TARGET from the clone over SOURCE, creating
   directories, printing `'TARGET' -> 'SOURCE'`. A TARGET which is not in the storage prints
   `file ... doesn't exist in repository, it might be worth to remove it from config file`.
3. `files pulled`, `final url <url>`.

Local files are overwritten without a backup. The config itself is normally in the list, so `pull`
also updates the config.

### `gits url`

Prints `final url <url>`: the web address of the directory of this project in the storage, to be
opened with ctrl+click. No clone.

```
GITSTORAGESOURCE=git@github.com:stopsopa/gitstorage.git
GITSTORAGETARGETDIR=git@github.com:stopsopa__gitstorage.git

final url https://github.com/stopsopa/gitstorage/tree/master/git@github.com:stopsopa__gitstorage.git
```

`git@HOST:OWNER/REPO.git` becomes `https://HOST/OWNER/REPO`, then `/tree/master/<dir>` when the
host is GitHub and `/raw/master/<dir>` otherwise. The branch is always `master`. (The repository
name is cut at its first dot, so a repository like `stopsopa.github.io` gives a wrong url.)

### `gits state`

The overview of all projects below the current directory. This is the entry point of the daily
routine: run it in `~/Workspace`, see which projects are out of sync, paste the printed
`cd ... / gits diff` into another terminal.

**The `find` which is executed:**

```bash
find . -type d -name 'node_modules' -prune -o -type f -name "gitstorage-config.sh" -print \
  | grep "/.git/gitstorage-config.sh"
```

Every regular file named `gitstorage-config.sh` anywhere below the current directory, without
entering `node_modules`, then only those which sit directly in a directory named `.git`. Symlinks
are not followed. The list is trimmed, sorted and deduplicated (`sort -u`). One path is always
added by hand: `./SPECIAL_storage/SPECIAL_storage/.git/gitstorage-config.sh` (a personal
hard-coded entry; when the command is run somewhere else it produces an error for that entry).

Nothing found: `nothing found`. Otherwise:

1. Two green lines of `=` with 11 empty lines between them: a visual separator from whatever was in
   the terminal before.
2. One temporary directory for the whole run, in the current directory. The storage is cloned into
   it **once**, when the first project needs it (`cloning directory ...`); the next projects reuse
   it (`directory ... already exist`).
3. For every found config, numbered `I : COUNT`:

   ```
   >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 2 : 10 >./SPECIAL_storage/SPECIAL_storage/.git/gitstorage-config.sh<

     cd "/Users/szdz/Workspace/SPECIAL_storage/SPECIAL_storage"
     gits diff
   ```

   - the header: delimiter, position, path of the config as found
   - two lines ready to be pasted: `cd` to the absolute path of the project, and `gits diff`
   - the config is sourced from the root of that project (its output is printed)
   - the clone is brought back to the state of the storage (`git clean -df`, `git checkout .`,
     between `before checkout vvv` and `after checkout ^^^`), so one project doesn't see the files
     of the previous one
   - every SOURCE is copied over TARGET, like in `diff`
   - result: `files are in sync` (green), or `files are not in sync` (red) followed by `git status`
     (no diff here, that is what the pasted `gits diff` is for), or
     `files are not in sync - at least one source file is missing`
4. Summary: `COUNT_SUCCESS : n` (green), `COUNT_ERROR   : n` (red). A project with a missing source
   file is counted in neither.
5. Cleanup. Exit code is always 0.

### `gits init`

Creates the config for the project in the current directory (it has to contain `.git`).

1. `.git/gitstorage-config.sh` already exists: say so, done.
2. Compute `GITSTORAGETARGETDIR` from the remote `origin`.
3. Clone the storage to a temporary directory (`.git/__rm__<random>`).
4. The storage already has `<GITSTORAGETARGETDIR>/gitstorage-config.sh` (the project was set up on
   another machine): copy it to `.git/`. This is how a new machine gets its files back:
   `gits init`, then `gits pull --yes`.
5. Otherwise generate a new config: a comment with the url of the project, the computed
   `GITSTORAGETARGETDIR`, and a `GITSTORAGELIST` with a few typical elements (`../.env`, `xx.cjs`,
   the config itself, `.vscode/settings.json`), plus a commented example of conditional elements.
6. Print what to do next (review the config).

Around that it also downloads or links helper scripts into `.git` (`wget.sh`, `gitstorage.sh`,
`gitstorage-core.sh`), which is only needed because the tool is a set of shell scripts.

### `gits add <file|directory>`

Registers files in the config. It changes only the config, nothing is copied or pushed, so the
result can be reviewed.

1. `find <path> -type f`: the file, or all files below the directory.
2. Read the config, find the block between `GITSTORAGELIST=(` and the closing `)`.
3. For every file not yet in the list (compared by SOURCE) append one line at the end of the block:
   - SOURCE: path relative to the directory of the config (`.git`)
   - TARGET: `$GITSTORAGETARGETDIR/` + the path as given, with every `../` removed
   - indentation and the way the variable is written (`$GITSTORAGETARGETDIR/` or
     `${GITSTORAGETARGETDIR}/`) are taken from the form used most often by the existing lines
4. Comments, empty lines and everything outside the block stay untouched.
5. Print the lines which were added.

### `gits move <old remote> <new remote>`

For the moment the remote `origin` of a project changes: its directory in the storage should be
renamed to match. The command changes nothing, it **prints the procedure**: the old and the new
name of the directory (both made with the `/` -> `__` rule), links to the storage, the lines to
change in the config, and shell commands which clone the storage, move the files, commit and push.

### Not carried over

| Command | What it does |
|---|---|
| `lock <path>` | copies files into `.git/xxlockdir` (to be registered with `add` afterwards) |
| `-c <config>` | use another config file |
| `existing` | for every `.git` below the current directory: fetch its config from the storage when the storage has one |
| `clean` | remove every `gitstorage-config.sh` and helper script below the current directory |
| `backup <dir>`, `restore <dir>` | copy the listed files to / from a local directory instead of the storage |
| `-r`, `-s` | name of the remote, url of the storage for `init` |

## 5. Output conventions

- green: good news (`files are in sync`, `files pushed`), red: problems, yellow: progress and the
  cleanup line
- output of `git` (clone progress, status, diff) is passed through
- `final url ...` closes every command which worked with one project
- the cleanup line is always the last one

## 6. Where the new implementation differs

From `CHANGES.md`:

| Topic | Original | `gits` |
|---|---|---|
| config | `.git/gitstorage-config.sh` | `.git/gits.sh`; the old one is migrated automatically the first time it is met, and by `gits migrate` / `gits migrate all` |
| the element which stores the config itself | `"gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"` | rewritten by the migration to `"gits.sh::$GITSTORAGETARGETDIR/gits.sh"` |
| `state`, `find` | look for `gitstorage-config.sh` | look for `.git/gits.sh` and `.git/gitstorage-config.sh` |
| encryption | none | an element written `SOURCE:e:TARGET` is stored encrypted; the work is done by a process listening on the unix socket `GITSTORAGETENCRYPTIONSOCKET` |
| shell which reads the config | bash, hard-coded | `GITSTORAGETESHELL`, default `/bin/bash` |
| `init` | generated text, helper scripts | restore from the storage, else the template from `GITSTORAGETEMPLATE`, else a built-in one; no helper scripts |
| self update | none | `gits --update` |
| new commands | | `gits find`, `gits migrate`, `gits migrate all` |

Decided while implementing (each one is a deliberate difference, not an accident):

| Topic | Original | `gits` | Why |
|---|---|---|---|
| `isinsync` | always exit 0 (bug) | 0 in sync, 1 not in sync, 2 error; prints nothing on stdout | the purpose in `PLAN.md` |
| `state`, exit code | always 0 | 1 when any project is not in sync or failed | usable in scripts |
| `state`, missing source file | counted nowhere | counted in `COUNT_ERROR` | the two numbers add up to the number of projects |
| `state`, hard-coded `SPECIAL_storage` entry | always added | not added | personal; it is found anyway when it is below the current directory |
| `state`, failing project | stops the whole run | counted as error, the run continues | one broken config doesn't hide the rest |
| new files in `diff` | only in `git status` | also in `git diff` (`git add --intent-to-add`) | the content of a new file is worth reviewing too |
| branch | `master` hard-coded (push and url) | the default branch of the storage | works with `main` |
| commit message of `push` | empty | `gits push <GITSTORAGETARGETDIR>` | the history of the storage says which project changed |
| `push` with a missing source file | exit 0 | the rest is pushed, exit 1 | the problem is not silent |
| TARGET | any path | must be relative, inside a directory, without `..` | a config can't write outside of the clone |
| url of a repository with dots in the name | cut at the first dot | only a trailing `.git` is removed | bug |
| `GITSTORAGESOURCE` | env or config | env only, checked before anything else | `PLAN.md`; `state` uses one clone for all projects |
| `REPO_DIR`, `realpath`, `openssl`, `node`, `python` | required | not needed | one binary; only `git` (and `curl`/`wget` for `init` with a url and `--update`) |
