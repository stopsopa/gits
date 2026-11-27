# Examples summary

Every use case of `gits`, to run command by command. Everything the examples create is in one
directory, `s/` in the root of this repository (ignored by git): the storage, the projects, the
keys. Keep `s/` open in the editor next to the terminal and watch what each step changes there.
Nothing outside of `s/` is touched: not your real storage, not your home, not your ssh-agent.

All commands are run from the root of this repository unless a `cd` says otherwise.

## Once per terminal

In the root of this repository (G and D below are made from the current directory: set
anywhere else they point to nothing, and `$G` answers `permission denied`):

```sh
[ -f compile.sh ] || echo "WRONG DIRECTORY: cd to the root of the gits repository first"

/bin/bash compile.sh                      # builds bin/<arch>/gits (prints its path as the last line)

export G="$PWD/$(ls bin/*/gits)"          # the binary, with an absolute path: the examples cd around
export D="$PWD/s"                         # the directory of the examples
$G --version
```

The storage. In real life it is a private repository on GitHub; here it is a directory, so you
can look into it after every push.

```sh
rm -rf $D && mkdir -p $D                  # start from nothing (also when the examples were run before)

git init -q $D/storage
# An ordinary repository refuses a push to the branch it has checked out. With this setting it
# accepts the push and updates its files: what gits stored is visible in s/storage right away.
git -C $D/storage config receive.denyCurrentBranch updateInstead

# From now on gits of THIS terminal uses the storage of the examples, not your real one.
# The previous value is kept to put it back at the end (kept only once, so this block can be run again).
SOURCE_BEFORE="${SOURCE_BEFORE:-$GITS_SOURCE}"
export GITS_SOURCE="$D/storage"

$G --help | tail -n 8                     # the table at the end: GITS_SOURCE is s/storage now
```

## Synopsis: all commands

```
$G state                      all projects below the current directory: in sync or not
$G find                       only the list of those projects
$G init                       create .git/gits.sh (from the storage, or from a template)
$G add [-e] FILE|DIR ...      register files in .git/gits.sh (in a terminal: a list to tick, ctrl+enter writes;
                              -e: as encrypted elements SOURCE:e:TARGET; no list: echo "" | $G add ...)
$G diff                       what differs between local files and the storage
$G isinsync                   the same, only the exit code: 0 in sync, 1 not, 2 error
$G push [--yes]               local files -> storage
$G pull [--yes]               storage -> local files
$G url                        where the project is in the storage
$G move OLD NEW               how to rename the directory in the storage
$G migrate [all]              .git/gitstorage-config.sh -> .git/gits.sh
$G events                     every lifecycle event, and which ones have a script now
$G --help | --version | --update [TAG|--check]
```

| Command | Run it in | Changes | Example |
|---|---|---|---|
| `init` | root of a project | creates `.git/gits.sh` | [case 001](#case-001-first_project_init_and_first_push), [case 003](#case-003-another_machine_init_and_pull), [case 010](#case-010-init_from_your_own_template) |
| `diff`, `isinsync` | root of a project | nothing | [case 001](#case-001-first_project_init_and_first_push), [case 002](#case-002-edit_diff_push) |
| `push --yes` | root of a project | the storage | [case 001](#case-001-first_project_init_and_first_push), [case 002](#case-002-edit_diff_push) |
| `pull --yes` | root of a project | local files | [case 003](#case-003-another_machine_init_and_pull) |
| `add` | root of a project | `.git/gits.sh` only | [case 004](#case-004-add_files_to_the_config) |
| `state`, `find` | any directory | nothing | [case 005](#case-005-many_projects_state_and_find) |
| `SOURCE:e:TARGET` | in the config | stored encrypted | [case 007](#case-007-encrypted_files), [case 008](#case-008-the_wrapper_starts_the_encoder_by_itself) |
| `migrate` | root of a project, or above many | renames the old config | [case 009](#case-009-config_of_the_old_tool) |
| `url`, `move` | root of a project | nothing | [case 011](#case-011-url_and_move) |
| `events`, `GITS_<COMMAND>_<EVENT>` | anywhere | your scripts run between the stages | [case 012](#case-012-lifecycle_events_your_scripts_between_the_stages) |

| Environment variable | Required | What it is | Example |
|---|---|---|---|
| `GITS_SOURCE` | yes | the storage: url or directory of a git repository | [Once per terminal](#once-per-terminal) |
| `GITS_ENCRYPTION_SOCKET` | for `:e:` | unix socket of the encoder process | [case 007](#case-007-encrypted_files) |
| `GITS_TEMPLATE` | no | your template for `init`: file or url | [case 010](#case-010-init_from_your_own_template) |
| `GITS_SHELL` | no | shell which runs the config and the lifecycle scripts, default `/bin/bash` | [case 006](#case-006-the_config_is_a_shell_script) |
| `GITS_START` | no | script which runs once, as the first thing of a command; a failure stops it | [encrypt/ENCRYPT_PROCESS.md](encrypt/ENCRYPT_PROCESS.md) |
| `GITS_EXIT` | no | script which runs as the last thing of every start of gits, however it ends | [encrypt/ENCRYPT_PROCESS.md](encrypt/ENCRYPT_PROCESS.md) |
| `GITS_<COMMAND>_<EVENT>`, `GITS_<COMMAND>_ALL`, `GITS_ALL` | no | path of a lifecycle script | [case 012](#case-012-lifecycle_events_your_scripts_between_the_stages) |

## case-001-first_project_init_and_first_push

A project is any git repository with a remote `origin`. The remote is never contacted: gits
only makes the name of the project's directory in the storage from it.

```sh
git init -q $D/project
cd $D/project
git remote add origin git@github.com:demo/project.git

# two files which must not be committed to the project, but which you don't want to lose
printf 'DB_USER=admin\nDB_PASS=secret\nDB_PORT=5432\n' > .env
echo 'local notes' > notes.txt
```

`init` creates the config. The storage has nothing for this project yet, so the built-in
template is used.

```sh
$G init
cat .git/gits.sh              # GITS_TARGETDIR is made from the remote: "/" became "__"
```

The config lists the files as `"SOURCE::TARGET"`. SOURCE is the file on this machine,
relative to `.git` (that is why project files start with `../`). TARGET is the path in the
storage. Write the list:

```sh
cat > .git/gits.sh <<'EOF'
GITS_TARGETDIR="git@github.com:demo__project.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env::$GITS_TARGETDIR/.env"
    "../notes.txt::$GITS_TARGETDIR/notes.txt"
)
EOF
```

The first line of the list stores the config itself. Keep it: it is what lets another machine
get the list back ([case 003](#case-003-another_machine_init_and_pull)).

```sh
$G isinsync; echo "exit code $?"      # 1: not in sync, the storage is empty. Prints nothing

# Clones the storage to a directory with a random name here in the project (watch s/project),
# copies the listed files into the clone, shows "git diff" + "git status" of the clone,
# then the local files which differ, and removes the clone.
$G diff; echo "exit code $?"

ls -A                                 # the temporary clone is gone
```

Nothing was stored yet. `push` without `--yes` only tells what it would do:

```sh
$G push; echo "exit code $?"          # 1: there is something to push
ls -A $D/storage                      # still only .git

$G push --yes                         # copies, commits, pushes to the storage
```

Look at the storage:

```sh
ls -A $D/storage
ls -A "$D/storage/git@github.com:demo__project.git"
cat "$D/storage/git@github.com:demo__project.git/.env"
git -C $D/storage log --oneline       # one commit: gits push git@github.com:demo__project.git

$G isinsync; echo "exit code $?"      # 0
$G diff                               # files are in sync
```

## case-002-edit_diff_push

The everyday loop: a file changed, see what differs, store it.

```sh
cd $D/project
printf 'DB_USER=admin\nDB_PASS=new-secret\nDB_PORT=5432\n' > .env

$G isinsync; echo "exit code $?"      # 1

# "-" is what is stored, "+" is what is here.
# At the end: "changed files:" with the absolute path of every local file which differs
# (in the terminal of vscode: ctrl + click opens the file), then the final url.
$G diff
```

```sh
$G push --yes

git -C $D/storage log --oneline       # two commits
git -C $D/storage show --stat HEAD    # only .env is in the second one

$G push --yes                         # nothing changed since: "files are in sync", no new commit
git -C $D/storage log --oneline       # still two
```

A file from the list which doesn't exist is an error, not a silent skip:

```sh
mv notes.txt notes.txt.away
$G diff; echo "exit code $?"          # source file ... doesn't exist, exit code 1
$G isinsync; echo "exit code $?"      # 1
mv notes.txt.away notes.txt
$G isinsync; echo "exit code $?"      # 0
```

## case-003-another_machine_init_and_pull

The same project cloned on another machine has none of the files. Here "another machine" is a
second directory with the same remote `origin`.

```sh
git init -q $D/project-other-machine
cd $D/project-other-machine
git remote add origin git@github.com:demo/project.git
ls -A                                 # only .git

# The storage has a gits.sh for this remote: init brings it back instead of making a new one.
$G init
cat .git/gits.sh                      # the list written in case 001
```

```sh
$G pull; echo "exit code $?"          # 1: there are files to pull. Without --yes nothing is written
ls -A                                 # still only .git

$G pull --yes                         # every TARGET is copied to its SOURCE
ls -A
cat .env                              # DB_PASS=new-secret
$G isinsync; echo "exit code $?"      # 0
```

A change travels from one machine to the other through the storage:

```sh
cd $D/project
echo 'more notes' >> notes.txt
$G push --yes

cd $D/project-other-machine
$G diff                               # here "-" is the newer, stored version
$G pull --yes
cat notes.txt                         # both lines
```

`pull` overwrites. A local edit which was not pushed is lost:

```sh
echo 'edit which was never pushed' >> notes.txt
$G pull --yes
cat notes.txt                         # the edit is gone
```

## case-004-add_files_to_the_config

`add` writes the lines of the list for you. It changes only `.git/gits.sh`: nothing is
copied, nothing is pushed.

```sh
cd $D/project
mkdir -p config/local
echo 'a' > config/a.json
echo 'b' > config/local/b.json
echo 'token' > .npmrc

# echo "" | : stdin is not a terminal, so everything found is added without asking
# (with a terminal on stdin a list to tick is shown: next block)
echo "" | $G add .npmrc                   # one file
echo "" | $G add config                   # a directory: every file in it, each as its own line
cat .git/gits.sh                      # three new lines, in the style the config already uses

echo "" | $G add config                   # again: nothing added, all are there already
git -C $D/storage log --oneline       # add stored nothing
```

```sh
$G diff                               # the new files and the changed config
$G push --yes
find "$D/storage/git@github.com:demo__project.git" -type f
```

With a terminal on stdin `add` first shows what it found and lets you choose. Run this
one line alone and play with the list: arrows move, `space` ticks, the column `add` says which
files go to the config, `enc` which of them as encrypted (`a` `n` `i` and `A` `N` `I`: all /
none / invert of each column). `ctrl+enter` writes (`ctrl+j` when your terminal doesn't tell
it from Enter), `q` leaves without writing. Whichever you choose, the next steps work:

```sh
echo 'c' > config/c.json
$G add config                         # only c.json is listed: a.json and b.json are in the config already
cat .git/gits.sh                      # after ctrl+enter: one more line; after q: nothing changed
```

SOURCE can also be a file outside of the project: an absolute path, or `~/...` for a file in
your home. Here a file elsewhere in `s/`:

```sh
mkdir -p $D/elsewhere
echo 'not in the project' > $D/elsewhere/tool.conf

echo "" | $G add $D/elsewhere/tool.conf
tail -n 4 .git/gits.sh                # SOURCE is written as ~/... because s/ is below your home; elsewhere it is the absolute path
$G push --yes
find "$D/storage/git@github.com:demo__project.git" -type f | grep tool.conf
```

## case-005-many_projects_state_and_find

`state` is for a directory with many projects (like `~/Workspace`): it finds every project
below the current directory and checks each one. Make a second project first:

```sh
git init -q $D/second
cd $D/second
git remote add origin git@github.com:demo/second.git
echo 'KEY=1' > .env
$G init
echo "" | $G add .env
$G push --yes
```

```sh
cd $D
$G find                               # ./project  ./project-other-machine  ./second

# The storage is cloned once (watch s/ for the directory with a random name) and used for all.
$G state; echo "exit code $?"         # 1: the other machine has not pulled what case 004 pushed
```

Bring the other machine up to date, then make two projects differ:

```sh
# Its local config is the old, shorter list. pull takes the config first, reads the list again,
# and so the files added in case 004 arrive in the same run.
(cd $D/project-other-machine && $G pull --yes)
$G state | tail -n 6                  # COUNT_ERROR : 0

echo 'KEY=2' > $D/second/.env
echo 'changed' >> $D/project/notes.txt

$G state; echo "exit code $?"         # 1
```

For every project `state` prints two lines to paste into another terminal:

```
  cd "/.../s/second"
  gits diff
```

```sh
(cd $D/second && $G push --yes)
(cd $D/project && $G push --yes)
(cd $D/project-other-machine && $G pull --yes)

$G state | tail -n 6                  # COUNT_ERROR : 0
```

`node_modules` is never entered, and a directory without `.git/gits.sh` is not a project:

```sh
mkdir -p $D/node_modules/pkg && git init -q $D/node_modules/pkg && touch $D/node_modules/pkg/.git/gits.sh
git init -q $D/no-config
$G find                               # the same three
rm -rf $D/node_modules $D/no-config
```

## case-006-the_config_is_a_shell_script

`.git/gits.sh` is executed (by `/bin/bash`, or by the shell in `GITS_SHELL`) from the
root of the project, and gits reads the two variables afterwards. So the list can be computed.

```sh
cd $D/second
echo 'dev' > .env.dev
echo 'prod' > .env.prod

cat > .git/gits.sh <<'EOF'
GITS_TARGETDIR="git@github.com:demo__second.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
)

# every .env* file which exists right now
for FILE in .env*; do
    GITS_LIST+=("../$FILE::$GITS_TARGETDIR/$FILE")
done

echo "config: ${#GITS_LIST[@]} elements"
EOF
```

```sh
$G push --yes                         # the line printed by the config is shown: 4 elements
find "$D/storage/git@github.com:demo__second.git" -type f

echo 'test' > .env.test               # a new file is picked up without touching the config
$G diff | tail -n 8                   # changed files: .env.test

$G isinsync; echo "exit code $?"      # 1, and silent: output of the config is not shown here
$G push --yes
```

```sh
GITS_SHELL=/bin/zsh $G isinsync; echo "exit code $?"     # the same config, run by zsh
```

## case-007-encrypted_files

An element written `SOURCE:e:TARGET` is stored encrypted. gits does not encrypt: it sends
`encode` / `decode` requests to the encoder process of `submodules/encrypt`, which listens on
the unix socket named in `GITS_ENCRYPTION_SOCKET` and encrypts with an ssh key held by
`ssh-agent`. Needs Node.js >= 22.18 and the submodule (`git submodule update --init submodules/encrypt`).

Back to the root of this repository, then a demo key and a private agent, both in `s/`. Your
own agent and keys are not touched, and `SSH_AUTH_SOCK` of this terminal is not changed either
(git may need your own agent to sign commits): the private agent is named in front of every
command which has to talk to it, as `SSH_AUTH_SOCK=$A`.

```sh
cd $D/..

# a demo key pair without a passphrase: s/key (private) and s/key.pub (public)
ssh-keygen -q -t ed25519 -N "" -C gits-demo -f $D/key

# A second ssh-agent, only for the examples, listening on s/agent.sock.
# What it prints (its pid) is kept in s/agent.env for stopping it.
export A="$D/agent.sock"
ssh-agent -a $A > $D/agent.env

# SSH_AUTH_SOCK=$A in front: this one command talks to the private agent.
# Never run ssh-add for the demo key without it: the key would land in your own agent.
SSH_AUTH_SOCK=$A ssh-add $D/key       # load the demo private key into the private agent
SSH_AUTH_SOCK=$A ssh-add -l           # what the private agent holds: only gits-demo
```

Start the encoder process. `tests/encoder/encoder-start.sh` can be called again and again:
when the process already answers, nothing is started.

```sh
export GITS_ENCRYPTION_SOCKET="$D/ssenc.sock"      # where it listens; gits reads the same variable
export GITS_ENCODER_SSH_KEY="$D/key.pub"                # the key everything is encrypted with

# the process remembers the agent it was started with: gits itself never needs SSH_AUTH_SOCK
SSH_AUTH_SOCK=$A /bin/bash tests/encoder/encoder-start.sh
SSH_AUTH_SOCK=$A /bin/bash tests/encoder/encoder-start.sh        # already running, nothing started
ls $D                                                   # ssenc.sock, ssenc.sock.pid, ssenc.sock.log
```

Mark `.env` of the first project as encrypted: `::` becomes `:e:`.

```sh
cd $D/project
sed -i.bak 's|"../.env::|"../.env:e:|' .git/gits.sh && rm .git/gits.sh.bak
grep env .git/gits.sh

$G diff | tail -n 12                  # a note: .env is marked :e: but it is stored not encrypted (yet)
$G push --yes                         # "(encrypted)" next to .env
```

In the storage the file is encrypted now, the local one is as it was:

```sh
cat "$D/storage/git@github.com:demo__project.git/.env"     # #ssenc1 ..., one encrypted line per line
cat .env                                                   # plain
tail -n 3 $D/ssenc.sock.log                                # the requests gits sent: decode, encode

$G isinsync; echo "exit code $?"      # 0: the stored file is decrypted for the comparison
```

Edit one line. The diff is shown in plain text, and in the storage only that line changes
(and the `#seal` line, which covers the whole file):

```sh
printf 'DB_USER=admin\nDB_PASS=new-secret\nDB_PORT=6543\n' > .env

# Before "git diff" runs, the stored .env is decrypted inside of the temporary clone
# (that decrypted copy is never pushed). So both sides of the diff are plain text.
$G diff                               # -DB_PORT=5432  +DB_PORT=6543, nothing encrypted on the screen

# push: .env is copied next to the stored file under a name which doesn't exist (.env.hash...),
# encrypted over the stored file, and the copy is removed
$G push --yes
git -C $D/storage show HEAD           # two lines changed: the edited one and #seal
```

The other machine gets it decrypted:

```sh
cd $D/project-other-machine
# The local config here still says "::" for .env. pull takes the stored config first (with ":e:"),
# reads the list again and only then copies .env - decrypted. A file is never copied encrypted.
$G pull --yes
cat .env                              # plain, DB_PORT=6543
grep env .git/gits.sh                 # :e:
```

Without the encoder process nothing encrypted can be read or written, and nothing is damaged:

```sh
(cd $D/.. && /bin/bash tests/encoder/encoder-stop.sh)

$G diff; echo "exit code $?"          # can't connect to the encoder process, exit code 1
$G isinsync; echo "exit code $?"      # 2: an error, not "not in sync"
cat .env                              # untouched

(cd $D/.. && SSH_AUTH_SOCK=$A /bin/bash tests/encoder/encoder-start.sh)
$G isinsync; echo "exit code $?"      # 0
```

## case-008-the_wrapper_starts_the_encoder_by_itself

`gits.sh` in the root of this repository is a wrapper around the binary: when
`GITS_ENCODER_SSH_KEY` is defined it makes sure the encoder process runs, then it calls the
binary with the same arguments. Do [case 007](#case-007-encrypted_files) first.

```sh
(cd $D/.. && /bin/bash tests/encoder/encoder-stop.sh)       # nothing runs now

export GITS_BIN="$G"
W="$D/../gits.sh"

cd $D/project
# SSH_AUTH_SOCK=$A only because the demo key is in the private agent;
# with your real key in your own agent it is just: gits isinsync
SSH_AUTH_SOCK=$A /bin/bash $W isinsync; echo "exit code $?"     # 0, and silent: the process was started on the way
cat $D/ssenc.sock.pid

SSH_AUTH_SOCK=$A /bin/bash $W isinsync; echo "exit code $?"     # the same process is used again
cat $D/ssenc.sock.pid
```

For everyday use it is an alias, so that `gits` means the wrapper:

```
export GITS_BIN="/path/to/gits"
export GITS_ENCODER_SSH_KEY="~/.ssh/id_ed25519.pub"
alias gits='/bin/bash "/path/to/this/repository/gits.sh"'
```

## case-009-config_of_the_old_tool

The old tool (`gitstorage.sh`) kept its config in `.git/gitstorage-config.sh`, and its two
variables were called `GITSTORAGETARGETDIR` and `GITSTORAGELIST`. Such a project is found and
migrated: the file becomes `.git/gits.sh`, the line which stores the config itself gets the new
name, and the two variables are renamed. Nothing else in the file is touched.

```sh
git init -q $D/old
cd $D/old
git remote add origin git@github.com:demo/old.git
echo 'old project' > file.txt

cat > .git/gitstorage-config.sh <<'EOF'
GITSTORAGETARGETDIR="git@github.com:demo__old.git"

GITSTORAGELIST=(
    "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
)
EOF
```

```sh
$G migrate
ls .git | grep -E 'gits|gitstorage'   # only gits.sh
cat .git/gits.sh                      # GITS_TARGETDIR, GITS_LIST, "gits.sh::$GITS_TARGETDIR/gits.sh"
$G migrate                            # nothing to migrate
$G push --yes
```

The same happens by itself when any command meets an old config, and `migrate all` does it for
every project below the current directory:

```sh
# make it an old one again
cat > .git/gitstorage-config.sh <<'EOF'
GITSTORAGETARGETDIR="git@github.com:demo__old.git"

GITSTORAGELIST=(
    "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
)
EOF
rm .git/gits.sh

cd $D
$G migrate all
ls old/.git | grep -E 'gits|gitstorage'
```

A config which is `.git/gits.sh` already but still uses the two old names works as it is; the
old names of the env vars (`GITSTORAGESOURCE`, ...) are read too when the new ones are not defined.

## case-010-init_from_your_own_template

`GITS_TEMPLATE` is a file (or a url) used by `init` for a project the storage doesn't know
yet. Only the line starting with `GITS_TARGETDIR=` is replaced.

```sh
cat > $D/template.sh <<'EOF'
# my template
GITS_TARGETDIR="replaced by init"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../.env::$GITS_TARGETDIR/.env"
)
EOF

git init -q $D/templated
cd $D/templated
git remote add origin git@github.com:demo/templated.git

GITS_TEMPLATE="$D/template.sh" $G init
cat .git/gits.sh                      # GITS_TARGETDIR="git@github.com:demo__templated.git"

$G init                               # already there: nothing is changed
```

## case-011-url_and_move

```sh
cd $D/project
$G url                                # for a storage on GitHub this is a link to the directory of the project
```

When the remote of a project changes, its directory in the storage has to be renamed. `move`
changes nothing, it prints the commands to do it:

```sh
$G move git@github.com:demo/project.git git@github.com:demo/renamed.git
```

## case-012-lifecycle_events_your_scripts_between_the_stages

Every command is a chain of stages, and between them gits runs your scripts. The name of a
variable says when (`GITS_<COMMAND>_<EVENT>`), its value is the path of the script.
Everything about it: [LIFECYCLE.md](../LIFECYCLE.md). The scripts of this case are in `s/events/`.

```sh
cd $D/project
mkdir -p $D/events

$G events | head -n 30                # every event of every command; "-" means: no script
```

A script for one event. It gets what gits knows as env vars:

```sh
cat > $D/events/after-push.sh <<'EOF'
echo ">>> after-push.sh: commit ${GITS_EVENT_COMMIT} is in the storage, directory ${GITS_TARGETDIR}"
EOF

export GITS_PUSH_AFTER_PUSH="$D/events/after-push.sh"

echo 'a new line' >> notes.txt
$G push --yes | tail -n 8             # the line of the script is there, after the push
$G events | grep GITS_PUSH_AFTER_PUSH # now it shows the path
```

A `BEFORE_*` script can say no. This one refuses the push while a file has `CHANGE_ME` in it:

```sh
cat > $D/events/check.sh <<'EOF'
if grep -q 'CHANGE_ME' "${GITS_EVENT_PROJECT_DIR}/notes.txt"; then
    echo ">>> check.sh: notes.txt still has CHANGE_ME in it, not pushing"
    exit 1
fi
EOF

export GITS_PUSH_BEFORE_PUSH="$D/events/check.sh"

echo 'CHANGE_ME' >> notes.txt
$G push --yes; echo "exit code $?"    # stopped: exit code 1, and after-push.sh did not run
git -C $D/storage log --oneline | head -n 2     # no new commit
ls -A                                 # the temporary clone is removed anyway

sed -i.bak '/CHANGE_ME/d' notes.txt && rm notes.txt.bak
echo 'fixed' >> notes.txt
$G push --yes | tail -n 8             # now it goes through
```

One script for every event: `GITS_ALL`. It writes a line per event, which shows the whole
lifecycle of a command, numbered:

```sh
cat > $D/events/log.sh <<'EOF'
echo "[${GITS_EVENT_SEQ}] ${GITS_EVENT} #${GITS_EVENT_INDEX} ${*:3}" >> "${GITS_EVENT_PWD}/../events.log"
EOF

unset GITS_PUSH_AFTER_PUSH GITS_PUSH_BEFORE_PUSH
export GITS_ALL="$D/events/log.sh"

$G diff > /dev/null
cat $D/events.log                     # START, CONFIG_LOADED, BEFORE_CLONE ... END, with their arguments
```

To see everything a script gets, dump its environment (the temporary directory, the file being
copied, the whole list, ...):

```sh
cat > $D/events/dump.sh <<'EOF'
{
    echo "arguments: ${*}"
    env | grep -E '^GITS_(EVENT|SOURCE|SHELL|TARGETDIR)' | sort
} > "${GITS_EVENT_PWD}/../dump-${GITS_EVENT_NAME}.txt"
EOF

GITS_DIFF_BEFORE_COPY="$D/events/dump.sh" $G diff > /dev/null
cat $D/dump-BEFORE_COPY.txt           # the last BEFORE_COPY of the run: GITS_EVENT_FILE_*, GITS_EVENT_TEMP_DIR ...
```

A project can carry its own scripts: the same variables in `.git/gits.sh`.

```sh
unset GITS_ALL
rm -f $D/events.log

cp $D/events/log.sh .git/log.sh
cat >> .git/gits.sh <<'EOF'

# a script only of this project, with a path relative to the root of the project
GITS_DIFF_ALL=".git/log.sh"
EOF

$G diff > /dev/null
cat $D/events.log                     # from CONFIG_LOADED on: the config is not known before it
```

Some stages are scripts themselves and can be replaced. `state` and `find` look for projects
with a default script (`events/defaults/FIND.sh` in the repository); here another one, which
only knows one project:

```sh
cd $D
$G find                               # the default: every project below

cat > $D/events/find.sh <<'EOF'
echo "./second/.git/gits.sh"
EOF

GITS_FIND_FIND="$D/events/find.sh" $G find      # only ./second
```

An example script of every event, each with everything it gets documented at the top:

```sh
$G events --examples $D/events-examples
ls $D/events-examples | head
sed -n 1,25p $D/events-examples/GITS_PUSH_BEFORE_PUSH.sh
```

## Clean up

```sh
cd $D/..

/bin/bash tests/encoder/encoder-stop.sh                                  # the encoder process; fine to call when it does not run

# the private agent of case 007, by the pid it printed when it started
[ -f $D/agent.env ] && kill "$(grep -o 'SSH_AGENT_PID=[0-9]*' $D/agent.env | cut -d = -f 2)"

rm -rf $D

# put the terminal back (or just open a new one)
export GITS_SOURCE="$SOURCE_BEFORE"
unset GITS_ENCRYPTION_SOCKET GITS_ENCODER_SSH_KEY GITS_BIN A
unset GITS_ALL GITS_PUSH_AFTER_PUSH GITS_PUSH_BEFORE_PUSH
```
