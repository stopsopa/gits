
In this document we will discuss desired changes from original implementation:

first of all we will have to have different name for config location .git/gitstorage-config.sh

it should be .git/gits.sh

we will also have to have `gits migrate` command which will migrate .git/gitstorage-config.sh to .git/gits.sh

but remember that .git/gitstorage-config.sh normally ALWAYS have row ` "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"` in the GITSTORAGELIST

which is there to store that config file with the tool itself

we will have to find it during migrate and replace with 

 "gits.sh::$GITSTORAGETARGETDIR/gits.sh"

 all pretty much should stay the same

Actually migration should kick in evry time gits will be in position for looking for .git/gits.sh and it won't find it but it will find .git/gitstorage-config.sh, then automigration should kick in

Also knowing this our main `find` behind `gits state` should look for directories containing .git/gits.sh and/or .git/gitstorage-config.sh

after successful migration old .git/gitstorage-config.sh should be removed

we could also have command `gits migrate all` which would execute `find` as the `gits state` but looking only for .git/gitstorage-config.sh and then it would execute migration on all of them and that's all.

# changed gits init

Obviously `gits init` shouldn't generate .git/gitstorage-config.sh but .git/gits.sh

# encryption

I would like to introduce encryption for individual files when defining list in GITSTORAGELIST.

we have to figure out new special notation for list in GITSTORAGELIST for each .git/gits.sh

when asked for implementation first initiate conversation about that aspec, propose some formats to indicate that particular file sholuld be encrypted...

Actually I know it should be :

when that

```
"gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"
```

then given file is not encrypted

but when defined like

```
"gitstorage-config.sh:e:$GITSTORAGETARGETDIR/gitstorage-config.sh"
```

then just before pushing to external repo file will have to be encrypted

We will use library from submodules/encrypt directory to encrypt (use with --seal flag from submodules/encrypt)

For encryption we will have to be little bit more clever:

becasue normally when doing `gits diff` we clone GITSTORAGESOURCE then we iterate over GITSTORAGELIST from .git/gitstorage-config.sh (in new implementation in .git/gits.sh) and we just copy SOURCE to TARGET for each elemenet on the list.

But now we will do the same for diff. 

But for push first state is the same but before doing git push we have encrypt these files

so the first part with normally is similar to `git diff` we will have to do something like:

sopy SOURCE to TARGET.raw and then encrypt 

```
$S encrypt --fresh --seal --password-file s/password.txt -i TARGET.raw -o TARGET
```

(look how to this encryption works in submodules/encrypt/examples/SUMMARY.md, pay attention to --seal flag - we have to use this one to encrypt in the way that in final git diff on new commit we will see how only in changed lines we can see encryption change)

Also for `gits diff` we have to decrypt, but that can be done in place: just clone then iterate over GITSTORAGELIST and copy SOURCE to TARGET and show diff.

Where `gits pull` will have to do what `gits diff` do and then decode each file with `:e:` and then copy from that repostiory GITSTORAGETARGETDIR from directory GITSTORAGETARGETDIR files specified in GITSTORAGELIST from TARGET to SOURCE.

# livecycle events

Actually Regarding encoding I don't want the rust process to call any processes, 
I would like it rather to look for env var GITSTORAGETENCRYPTIONSOCKET and then once given process would send requests to socket in the form of 

```
echo "encode \"$T/plain/01.yml\" \"$T/encrypted/01.yml.enc\"" | nc -U $T/ssenc.sock
echo "decode \"$T/encrypted/01.yml.enc\" \"$T/decoded/01.yml\"" | nc -U $T/ssenc.sock
```

(warning: nc is used only to send string to the socket but rust would connect to it directly)

look into `## socket-002-encoder_process_on_a_socket` chapter in submodules/encrypt/examples/SUMMARY.md

to understand how socket will be launched for rust to allow it to talk to it.

so internally we will achieve behind that socket

```
$S encrypt --fresh --seal --password-file s/password.txt -i TARGET.raw -o TARGET
```
but you don't have to worry about it, just worry about generating TARGET.raw but there might exist file *.raw so really generate temporary file like TARGET.hashc8874 (just an example but you have to find path which doesn't exist and only then copy and then send for encryption, once encryption is done remove TARGET.hashc8874

so we will have to juggle these files just before encryption, then encrypt and then remove that temporary TARGET.hashc8874

so we will be needing to decrypt for `gits diff` and `gits pull --yes`. And we will have to encrypt just before git commit and git push for `gits push --yes`



# auto update, --update argument

see how to implement in rust --update -> submodules/xx/UPDATE_IMPLEMENTATION.md

# testing

create tests each in separate directory - similarly like it starts in submodules/xx/test.sh and how each test case is spread across separate directories in submodules/xx/test.

for testing generally our rust implementation we will have to define for each test like test/test001/GITSTORAGESOURCE by running

```

rm -rf test/test001/GITSTORAGESOURCE
cd test/test001/GITSTORAGESOURCE
git init .


```

then for given test we define 

```
export GITSTORAGESOURCE=test/test001/GITSTORAGESOURCE

```

and then we can create another directory with structure

```

rm -rf test/test001/repo
cd test/test001/repo
git init .
echo 'test file' > test.txt
echo 'xx config' > .git/xx.ts
cat <<EEE > .git/gitstorage-config.sh

GITSTORAGETARGETDIR="git@github.com:tmp_repo.git"
GITSTORAGELIST=(

    "gits.sh::$GITSTORAGETARGETDIR/gits.sh"
    ..
    ..
)    
EEE
and then 

../../target/path_to_rust_implementation/gits diff

# capture the output and validate with test

```






# gits diff: list of changed files

`gits diff` (the command `gits state` prints to paste for every project which is not in sync) shows
`git diff` and `git status` of the temporary clone and the final url at the end. The paths in that
output are paths inside of the storage, not the files on this machine.

Just above the final url print a block with the absolute paths of the local files (SOURCE) which
differ from what is stored, one per line:

```
changed files:
  /Users/szdz/Workspace/pull.sh
  /Users/szdz/.agents/.skill-lock.json
  /Users/szdz/.claude/settings.json

final url https://github.com/stopsopa/gitstorage/tree/master/git@github.com:stopsopa__gitstorage.git
```

This way, when `gits diff` is executed in the terminal of vscode, ctrl + click on a path opens the file.

- only the files which differ are listed (modified, or new for the storage), in the order of GITSTORAGELIST
- the path is the SOURCE resolved on this machine (`~/` expanded, relative ones resolved from `.git`),
  never a path in the temporary clone: that one is removed when the command ends
- for an encrypted element (`SOURCE:e:TARGET`) it is the plain local file too
- nothing is printed when the files are in sync
- a source file which doesn't exist is not in the list, it is reported as an error above

# all variables start with GITS_

Every variable of the project is prefixed `GITS_` now, nothing starts with `GITSTORAGE` any more:

| old | new |
|---|---|
| `GITSTORAGESOURCE` | `GITS_SOURCE` |
| `GITSTORAGETESHELL` | `GITS_SHELL` |
| `GITSTORAGETENCRYPTIONSOCKET` | `GITS_ENCRYPTION_SOCKET` |
| `GITSTORAGETEMPLATE` | `GITS_TEMPLATE` |
| `GITSTORAGETARGETDIR` | `GITS_TARGETDIR` |
| `GITSTORAGELIST` | `GITS_LIST` |

The chapters above were written before the rename and still use the old names.
The old names keep working when the new one is not defined (environment and config),
`gits migrate` renames the two variables inside of a config.

# lifecycle events

Scripts between the stages of every command: `GITS_<COMMAND>_<EVENT>`, `GITS_<COMMAND>_ALL`, `GITS_ALL`,
defined in the environment or in `.git/gits.sh`, executed by the shell from `GITS_SHELL`.

- requirements and decisions: IMPLEMENT_EVENTS.md
- documentation, with a graph of every command: LIFECYCLE.md
- list of all events: `gits events`, example scripts: events/examples/, defaults: events/defaults/

# gits add: a list to tick

`gits add <file|directory> ...` in a terminal doesn't write straight away any more. It shows
the files it found (the ones which are not in the config yet, with paths relative to the
project) and waits:

```
    add enc  file
    [x] [ ]  .env
  > [x] [x]  config/secret.json
    [ ]      config/public.json
```

- column `add`: the file goes to `GITS_LIST`; column `enc`: as `SOURCE:e:TARGET`. The box `enc`
  exists only in a ticked row, the paths stay in one column anyway
- arrows move (left / right between the two boxes), `space` ticks
- `a` `n` `i`: all / none / invert in the column `add`; `A` `N` `I`: the same in the column `enc`,
  among the ticked rows
- only `ctrl+enter` writes the config. Enter alone does nothing. gits asks the terminal to tell the
  two apart (kitty keyboard protocol, modifyOtherKeys of xterm); for a terminal which can't:
  `ctrl+j`, `ctrl+s`
- `q`, `esc`: nothing is written, exit code 1. `ctrl+c`: exit code 130
- at the beginning everything is ticked
- `-e`: the files are registered as encrypted elements (`SOURCE:e:TARGET`). With the list it
  ticks `enc` of every row at the beginning, without the list it applies to every file
- the list is shown only when stdin is a terminal: `echo "" | gits add ...` (or a script) adds
  everything found, as before. `add` takes no `--yes`
- paths from stdin: `find ... | gits add`, `find ... | gits add -e`. One file per line; a
  directory in the list is skipped (not walked), empty lines are skipped, arguments are still taken
- code: `src/menu.rs`, tests: `tests/test014` (keys pressed in a pseudo terminal by `tests/terminal.py`)

# --help: every env var, three columns

The table of env vars in `gits --help` lists every variable gits reacts to: its own six, the
four names from before the rename, `HOME`, `NO_COLOR`, `GITS_EVENT_RUNNING` and the 133 variables
of lifecycle events.

- column 1: the name with its value exactly as it is in the shell: `NAME (not defined)`,
  `NAME="" (empty)`, `NAME="value"` (was: two columns, and empty looked like not defined)
- column 2: the default
- column 3: the value gits uses in the end (the value, the default, where it came from when it
  was read from an old name, or what happens without it)

# gits list

`gits list [--mode <variable>]`: the projects `gits state` would visit, absolute paths, one per
line and nothing else on stdout: `gits list | /bin/bash script.sh`.

- works without `GITS_SOURCE` (it only searches)
- `--mode`: the name of the variable whose script does the search: `GITS_STATE_FIND` (default),
  `GITS_FIND_FIND`, `GITS_MIGRATE_FIND`. Not defined: the built-in search
- no other lifecycle script runs (no `START`, `FOUND`, `END`, `*_ALL`)
- tests: `tests/test004`

# GITS_PULL_TO_SYNC: the clone of the storage is kept

Not in the original. Every command cloned the whole storage into a directory with a random name
and removed it. With `GITS_PULL_TO_SYNC=<directory>` (absolute or `~/...`) all commands use that
directory instead:

- no clone there yet: `git clone`
- a clone of `GITS_SOURCE` there: `git fetch`, then the branch (the one the clone started with,
  the default branch of the storage) is reset to what origin has and the directory is cleaned.
  Not `git pull`: a commit left by a previous run (the decrypted view, a push which failed) must
  not be merged and pushed later
- the same reset and clean at the end of every command, instead of removing the directory
- anything else in that directory (not empty and not a clone, a clone of another repository):
  an error, nothing is touched
- limits: two gits commands at the same time would share the directory (no lock). Objects of
  local commits with decrypted files can stay in `.git` of the kept clone until git collects them
- `gits --help` lists it: 7 variables of gits itself now
- code: `src/ops.rs` (`Temp`, `Storage::clone`, `restore`), tests: `tests/test015`
