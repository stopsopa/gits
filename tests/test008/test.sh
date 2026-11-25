#
# What is tested here: "gits init" with a template, "gits url", "gits move", and that the config
# (.git/gits.sh) really is a shell script executed by the shell from GITSTORAGETESHELL.
#
# In this order:
#
#   1. gits init where it can't work: a directory which is not a repository, a repository without
#      remote "origin". An error, and nothing is created.
#   2. gits init with GITSTORAGETEMPLATE: a template which doesn't exist, a template without the line
#      GITSTORAGETARGETDIR=, then a good one. In the good one only the value of GITSTORAGETARGETDIR is
#      replaced, the rest is copied as it is. Also a template given as "~/..." .
#   3. gits url: prints where the project is in the storage, creates nothing.
#   4. gits move: prints the steps to move a project to another remote, changes nothing.
#   5. the config is executed: from the root of the project, its stdout and stderr are shown, elements
#      added by a loop in the config are stored. isinsync doesn't show the stdout of the config.
#   6. GITSTORAGETESHELL: a wrapper shell which leaves a trace proves that it was used; empty value
#      means the default /bin/bash; a shell which doesn't exist is an error; zsh works too (when installed).
#   7. a config which calls "exit" can't be read: an error.
#
# /bin/bash tests/test008/test.sh
#
# Needs: the compiled binary (compile.sh). zsh is optional, its check is skipped when it is not installed.
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# where this file is (works in bash, zsh and sh): ${_DIR} is the directory of this test
_SHELL="$(ps -p $$ -o comm=)"; # bash || sh || zsh
_SHELL="$(basename ${_SHELL//-/})"
case ${_SHELL} in
  zsh)
    _DIR="$( cd "$( dirname "${(%):-%x}" )" && pwd -P )"
    ;;
  sh)
    _DIR="$( cd "$( dirname "${0}" )" && pwd -P )"
    ;;
  *)
    _DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P )"
    ;;
esac

# what the previous run left (kept after the test to look at it, ignored by git: .gitignore next to this file)
if [[ -d "${_DIR}/tmp" ]]; then
  chmod -R u+w "${_DIR}/tmp"
  rm -rf "${_DIR}/tmp"
fi

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, an empty storage in ${WORK}/GITSTORAGESOURCE, function "test"
# and the helpers used inside of COMMAND (gits, has, listing, storage, storage_commits)
source "${_DIR}/../_lib.sh"

# name of the directory of the project in the storage: what gits makes from the remote
# "git@github.com:tmp/repo.git" used below (every "/" changed to "__")
D="git@github.com:tmp__repo.git"

# ---------- init: where it can't work ----------

# a directory which is not a git repository at all
mkdir notrepo

# init needs the .git directory in the current directory: here there is none.
# "has" prints the fragment only when it is in the output of gits; exit code 1 is the one of gits
# (pipefail), an error.
COMMAND='cd notrepo && gits init 2>&1 | has "you have to execute it in the directory where .git exists"'
EXPECTED_STDOUT="you have to execute it in the directory where .git exists"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init outside of a repository"

# a repository, but without any remote
mkdir noremote
git -C noremote init -q .

# the part of the error message which is looked for (in a variable because of the quotes in it)
F1="has no remote 'origin'"

# GITSTORAGETARGETDIR is made from the url of remote "origin": without it init can't make the config.
# Error, exit code 1.
COMMAND='cd noremote && gits init 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init without remote origin"

# "listing" prints the names in the directory in one line: only .git is there, the failed init
# left no other file or directory next to it
COMMAND='listing noremote'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init without remote origin: nothing created"

# ---------- init with a template ----------

# the project used in the rest of the test: an empty repository with remote origin, and we go into it
# (COMMANDs below run in ${WORK}/repo)
project repo "git@github.com:tmp/repo.git"
cd repo

# the template for the next checks. Quoted 'EEE': nothing is expanded here, $GITSTORAGETARGETDIR
# stays as text. The line with GITSTORAGETARGETDIR is indented and has a value which has to be replaced.
cat <<'EEE' > "${WORK}/template.sh"
# my template
  GITSTORAGETARGETDIR="will be replaced"
GITSTORAGELIST=(
    "gits.sh::$GITSTORAGETARGETDIR/gits.sh"
    "../from-template.txt::$GITSTORAGETARGETDIR/from-template.txt"
)
EEE

# GITSTORAGETEMPLATE points to a file which is not there: init says which path it tried and ends
# with 1, it doesn't fall back to the built-in template without a word
COMMAND='GITSTORAGETEMPLATE="${WORK}/missing.sh" gits init 2>&1 | has "template GITSTORAGETEMPLATE=>${WORK}/missing.sh<"'
EXPECTED_STDOUT="template GITSTORAGETEMPLATE=>${WORK}/missing.sh<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, template which doesn't exist"

# a file which exists but is not a template: no line starting with GITSTORAGETARGETDIR=
echo "no variable here" > "${WORK}/bad-template.sh"

# init has nothing to replace in such a template, so it refuses it: error, exit code 1
COMMAND='GITSTORAGETEMPLATE="${WORK}/bad-template.sh" gits init 2>&1 | has "there is no line starting with GITSTORAGETARGETDIR= in the template"'
EXPECTED_STDOUT="there is no line starting with GITSTORAGETARGETDIR= in the template"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, template without GITSTORAGETARGETDIR"

# after the two failed inits: the project still has only .git in it ("listing" prints ".git"),
# and .git has no gits.sh (the fragment "gits.sh" is looked for in the listing of .git and is not
# in the expected output: it must not be found)
COMMAND='listing; listing .git | has "gits.sh"'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "failed init creates nothing, no config"

# the good template: init says that the config was generated and from which template. Exit code 0.
COMMAND='GITSTORAGETEMPLATE="${WORK}/template.sh" gits init 2>&1 | has "generated (template ${WORK}/template.sh)"'
EXPECTED_STDOUT="generated (template ${WORK}/template.sh)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init with a template"

# the whole generated config, compared exactly: the comment, the indentation of the line and
# both elements are as in the template, only the value "will be replaced" became the directory
# made from the remote (${D})
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="# my template
  GITSTORAGETARGETDIR=\"${D}\"
GITSTORAGELIST=(
    \"gits.sh::\$GITSTORAGETARGETDIR/gits.sh\"
    \"../from-template.txt::\$GITSTORAGETARGETDIR/from-template.txt\"
)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "config made from the template: only GITSTORAGETARGETDIR is changed"

# again, with "~/" in the path of the template: the config made a moment ago is removed
# (init does nothing when it is there) and the template is copied to the home of the test
rm .git/gits.sh
cp "${WORK}/template.sh" "${HOME}/t.sh"

# the line the generated config has to contain
F1="GITSTORAGETARGETDIR=\"${D}\""

# the template given as "~/t.sh" in quotes: the shell doesn't expand it, gits has to (HOME of the
# test is ${WORK}/home). The output of init is not interesting here: first line is its exit code (0),
# second line proves that the config was made and has the right GITSTORAGETARGETDIR.
COMMAND='GITSTORAGETEMPLATE="~/t.sh" gits init > /dev/null 2>&1; echo "${?}"; cat .git/gits.sh | has "${F1}"'
EXPECTED_STDOUT="0
${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init with a template in home"

# ---------- url ----------

# gits url prints where the project is in the storage. The storage of the tests is a local
# directory, not github, so there is no web address: the path of the storage and the name of the
# directory in it. The second line (".git") is "listing": url created nothing in the project,
# also no temporary clone.
COMMAND='gits url 2>&1; listing'
EXPECTED_STDOUT="final url ${GITSTORAGESOURCE} (directory ${D})
.git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "url of a storage which is a directory, url creates nothing"

# ---------- move ----------

# the lines "gits move" has to print for moving the project from remote
# git@xxx:project/source-repo.git to git@yyy:other/target-repo.git:
# F1, F2 - old and new name of the directory in the storage ("/" -> "__")
# F3, F4 - how to clone the storage and rename the directory in it
# F5     - how to point the project to the new remote
# F6     - the new line for .git/gits.sh
F1="from: git@xxx:project__source-repo.git"
F2="to:   git@yyy:other__target-repo.git"
F3="git clone \"${GITSTORAGESOURCE}\" ."
F4='git mv "git@xxx:project__source-repo.git" "git@yyy:other__target-repo.git"'
F5='git remote set-url origin "git@yyy:other/target-repo.git"'
F6='GITSTORAGETARGETDIR="git@yyy:other__target-repo.git"'

# gits move only prints instructions. All six fragments have to be in its output (has prints
# them in the order they were given), exit code 0.
COMMAND='gits move git@xxx:project/source-repo.git git@yyy:other/target-repo.git 2>&1 | has "${F1}" "${F2}" "${F3}" "${F4}" "${F5}" "${F6}"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}
${F4}
${F5}
${F6}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "move: old directory, new directory, clone of the storage, rename, remote, config"

# move did nothing by itself: the storage still has 0 commits and the project still only .git
COMMAND='storage_commits; listing'
EXPECTED_STDOUT="0
.git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "move changes nothing and creates nothing"

# move needs both remotes: with one argument it prints the usage and ends with 1
COMMAND='gits move only-one 2>&1 | has "usage: gits move <old remote> <new remote>"'
EXPECTED_STDOUT="usage: gits move <old remote> <new remote>"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "move with one argument"

# ---------- the config is executed: from the root of the project, by the shell from GITSTORAGETESHELL ----------

# two files which the config below will find; three.txt is not created on purpose
echo "one" > one.txt
echo "two" > two.txt
# a config which is more than two assignments. Not quoted EEE: ${D} is put in now, everything
# with a backslash (\$...) stays for the moment when gits executes the config. It:
#   - prints a line with its working directory to stdout
#   - prints a line to stderr
#   - adds an element to the list for each of one.txt, two.txt, three.txt which exists
cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"

echo "config says: pwd is \$(pwd)"
echo "config warns on stderr" >&2

GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
)

# elements computed while the config runs
for NAME in one two three; do
  if [ -f "\${NAME}.txt" ]; then
    GITSTORAGELIST+=("../\${NAME}.txt::\$GITSTORAGETARGETDIR/computed/\${NAME}.txt")
  fi
done
EEE

# what has to be seen in the output of push:
# F1 - the line the config printed to stdout, with the directory it was executed in: the root of the project
# F2 - the line the config printed to stderr
# F3 - an element which exists only because the loop in the config added it
F1="config says: pwd is ${WORK}/repo"
F2="config warns on stderr"
F3="'../two.txt' -> '${D}/computed/two.txt'"

# push with the computed config. The three fragments are there, exit code 0.
# "three.txt" is looked for too and is not in the expected output: the config added no element
# for it (the file doesn't exist), so nothing about it may be printed.
COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}" "${F3}" "three.txt"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "computed config, push: executed from the root of the project, its stdout and stderr are shown, computed element"

# a fresh clone of the storage in ${WORK}/look, and what is in the directory "computed" of the
# project: the two computed elements were really stored, and only them
COMMAND='storage "${WORK}/look" && listing "${WORK}/look/${D}/computed"'
EXPECTED_STDOUT="one.txt two.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored computed elements"

# isinsync answers only with the exit code (0: in sync, after the push above). stderr is thrown
# away here (the config writes to it), stdout has to be empty: the line the config prints to stdout
# is not passed through by isinsync.
COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "computed config, isinsync: stdout of the config is not shown"

# a "shell" of our own: a script which writes "called" to a log every time it is used and then
# passes all its arguments to the real bash. Not quoted EEE: ${WORK} is put in now, "\${@}" stays.
cat <<EEE > "${WORK}/myshell"
#!/bin/bash
echo "called" >> "${WORK}/myshell.log"
exec /bin/bash "\${@}"
EEE
# it is started as a program, so it has to be executable
chmod +x "${WORK}/myshell"

# isinsync with GITSTORAGETESHELL pointing to the wrapper. First line: exit code of gits (0, the
# config was read fine). Second line: the log has "called" exactly once, so gits executed the config
# with this shell and with nothing else.
COMMAND='GITSTORAGETESHELL="${WORK}/myshell" gits isinsync 2> /dev/null; echo "${?}"; cat "${WORK}/myshell.log"'
EXPECTED_STDOUT="0
called"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the config was executed by the shell from GITSTORAGETESHELL"

# GITSTORAGETESHELL defined but empty is the same as not defined: /bin/bash is used. Exit code 0,
# and the log still has one line only: the wrapper was not called this time.
COMMAND='GITSTORAGETESHELL="" gits isinsync 2> /dev/null; echo "${?}"; cat "${WORK}/myshell.log"'
EXPECTED_STDOUT="0
called"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "empty GITSTORAGETESHELL: default is used, the wrapper was not called again"

# the error which names the variable and the value which is wrong
F1="can't run shell GITSTORAGETESHELL=>${WORK}/no-such-shell<"

# a shell which doesn't exist can't execute the config: error with the path, exit code 1
COMMAND='GITSTORAGETESHELL="${WORK}/no-such-shell" gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "shell which doesn't exist"

# the same config executed by zsh, only where zsh is installed (CI installs it)
if command -v zsh > /dev/null 2>&1; then
  # GITSTORAGETESHELL is the full path of zsh. ZDOTDIR is the empty HOME of the test, so no startup
  # file of the developer is read. The config is valid zsh too: diff says "files are in sync"
  # (everything was pushed above) and ends with 0.
  COMMAND='ZDOTDIR="${HOME}" GITSTORAGETESHELL="$(command -v zsh)" gits diff 2>&1 | has "files are in sync"'
  EXPECTED_STDOUT="files are in sync"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "config executed by zsh"
fi

# "exit 0" added at the end of the config: the shell ends before gits gets the values from it
echo 'exit 0' >> .git/gits.sh

# gits notices that the config didn't run to its end and doesn't guess: error, exit code 1
COMMAND='gits diff 2>&1 | has "didn'"'"'t run to its end"'
EXPECTED_STDOUT="didn't run to its end"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "config which calls exit"

# the project at the end of the test: .git and the two files made above, no temporary clone
# left by any of the commands, also not by the ones which failed
COMMAND='listing'
EXPECTED_STDOUT=".git one.txt two.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing left behind at the end"
