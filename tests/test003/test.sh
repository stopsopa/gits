#
# The other direction: a second clone of the same project (think: another machine) gets everything
# back from the storage with "gits init" + "gits pull --yes".
#
# Two directories play two machines: "one" pushes, "two" pulls. Both have the same remote origin,
# so both use the same directory in the storage.
#
# What is tested, in this order:
#
#   1. setup: project "one" pushes its files (project file, file in .git, file in a subdirectory,
#      file in home, the config itself)
#   2. in project "two", which has nothing: init finds the config of this project in the storage
#      and restores it, instead of generating a new one
#   3. pull without --yes writes nothing; pull --yes copies every file from the storage to its
#      place, creating missing directories (also in home); afterwards the project is in sync
#   4. a change pushed from "one" is seen by diff in "two" and arrives with pull --yes
#   5. pull overwrites a local edit
#   6. an element of the list which doesn't exist in the storage: pull says so, creates nothing for it
#      and still ends with exit code 0; and because the config is in the list too, pull replaces the
#      edited config with the stored one
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test003/test.sh
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# _DIR: the directory of this file, whatever shell runs it and wherever it was called from
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

# Remove what the previous run of this test left in tests/testNNN/tmp. It is not removed at the end
# of the test, to look at it afterwards (ignored by git: .gitignore next to this file).
# chmod first: a test may leave a directory which is not writable.
if [[ -d "${_DIR}/tmp" ]]; then
  chmod -R u+w "${_DIR}/tmp"
  rm -rf "${_DIR}/tmp"
fi

# Shared setup: creates ${WORK} (= tmp/ next to this file) with an empty HOME, own git config and
# an empty storage repository in ${WORK}/GITSTORAGESOURCE, goes to ${WORK}, and defines function "test"
# (bash/test.sh) and the helpers used below (gits, has, listing, stored, storage_commits, project, ...)
source "${_DIR}/../_lib.sh"

# Directory of the project in the storage: remote origin with "/" replaced by "__".
D="git@github.com:tmp__repo.git"

# The first machine: project "one" with remote origin git@github.com:tmp/repo.git.
project one "git@github.com:tmp/repo.git"
cd one
# its files: one in the project, one in .git, one in home (two directories deep, to see later
# that pull creates them)
echo 'test file' > test.txt
echo 'xx config' > .git/xx.ts
mkdir -p "${HOME}/.config/app"
echo 'from home' > "${HOME}/.config/app/h.conf"
# The config of the project: the config itself, the three files above and a file two directories
# deep in the project (created just below).
cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"
GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
    "xx.ts::\$GITSTORAGETARGETDIR/xx.ts"
    "../test.txt::\$GITSTORAGETARGETDIR/test.txt"
    "../deep/dir/file.txt::\$GITSTORAGETARGETDIR/deep/dir/file.txt"
    "~/.config/app/h.conf::\$GITSTORAGETARGETDIR/home/h.conf"
)
EEE
# the file two directories deep
mkdir -p deep/dir
echo 'deep' > deep/dir/file.txt
# Everything goes to the storage. This is preparation, not a check: when it fails the test stops.
gits push --yes > /dev/null 2>&1 || fail "push from the first machine failed"
# back to ${WORK}, the first machine is done for now
cd ..

# "Another machine": a fresh project with the same remote and nothing else. The file in home is
# removed too (both "machines" share ${HOME}), so pull has to bring it back.
rm -rf "${HOME}/.config"
project two "git@github.com:tmp/repo.git"
cd two

# ---------- init restores the config from the storage ----------

# init looks into the storage first: there is a gits.sh in the directory of this project
# (found by the name made from remote origin), so it is copied to .git/gits.sh.
# Nothing is generated from a template.
COMMAND='gits init 2>&1 | has ".git/gits.sh restored from the storage: ${D}/gits.sh"'
EXPECTED_STDOUT=".git/gits.sh restored from the storage: ${D}/gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init restores the config from the storage"

# The restored config is identical to the one of the first machine (diff prints nothing),
# and init created nothing else: next to .git the project is still empty.
COMMAND='diff .git/gits.sh ../one/.git/gits.sh && listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "restored config is the one of the first machine, nothing else was created"

# ---------- pull ----------

# pull without --yes only looks: there are files to pull (exit code 1) and it says how to do it.
COMMAND='gits pull 2>&1 | has "If you are sure that you want to pull them: gits pull --yes"'
EXPECTED_STDOUT="If you are sure that you want to pull them: gits pull --yes"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "pull without --yes"

# ... no file was written
COMMAND='listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull without --yes: nothing is written"

# The real pull. Every copied file is printed as 'TARGET' -> 'SOURCE' (the other way round than push),
# one of them is checked, and "files pulled" at the end. Exit code 0.
COMMAND='gits pull --yes 2>&1 | has "'"'"'${D}/test.txt'"'"' -> '"'"'../test.txt'"'"'" "files pulled"'
EXPECTED_STDOUT="'${D}/test.txt' -> '../test.txt'
files pulled"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull --yes: what is copied"

# Every file is at its SOURCE with the content pushed by the first machine: in the project,
# in .git, in deep/dir (the directories didn't exist) and in home (~/.config/app didn't exist).
# The last line is the listing of the project: test.txt and deep are new, nothing else (no clone left).
COMMAND='cat test.txt .git/xx.ts deep/dir/file.txt "${HOME}/.config/app/h.conf" && listing'
EXPECTED_STDOUT="test file
xx config
deep
from home
.git deep test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pulled files: plain, in .git, in a new directory, in home (directories created)"

# after the pull the project is the same as the storage: 0, nothing printed
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync after pull"

# pull without --yes when there is nothing to pull: exit code 0
COMMAND='gits pull > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull without --yes, in sync"

# ---------- a change made on the first machine arrives on the second one ----------

# On the first machine one file is edited and pushed (preparation: stops the test when it fails),
# then back to the second machine.
cd ../one
echo 'changed on one' > test.txt
gits push --yes > /dev/null 2>&1 || fail "second push from the first machine failed"
cd ../two

# The second machine didn't change anything, but the storage did: diff shows the stored line
# with "-" and the (now older) local one with "+". Exit code 1.
COMMAND='gits diff 2>&1 | has "-changed on one" "+test file"'
EXPECTED_STDOUT="-changed on one
+test file"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff sees the change of the other machine: what is stored, what is here"

# pull --yes ends with 0 (first line, printed by echo) and the local file has the new content.
COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat test.txt'
EXPECTED_STDOUT="0
changed on one"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second pull"

# A local edit on the second machine, not pushed.
echo 'local edit' > test.txt

# pull doesn't ask and doesn't merge: the local edit is replaced by what is stored.
# That is what pull is for.
COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat test.txt'
EXPECTED_STDOUT="0
changed on one"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull overwrites local edits"

# ---------- an element the storage knows nothing about ----------

# One more element is appended to the local config: a file which was never pushed,
# so the storage has nothing at its TARGET.
cat <<EEE >> .git/gits.sh
GITSTORAGELIST+=("../new.txt::\$GITSTORAGETARGETDIR/new.txt")
EEE

# pull says that this file is not in the storage and carries on with the rest: exit code 0.
COMMAND='gits pull --yes 2>&1 | has "file '"'"'${D}/new.txt'"'"' doesn'"'"'t exist in the storage"'
EXPECTED_STDOUT="file '${D}/new.txt' doesn't exist in the storage"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull with an element missing in the storage"

# no new.txt appeared (no empty file was created for the element which is not stored)
COMMAND='listing'
EXPECTED_STDOUT=".git deep test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created for it"

# The config is an element of the list like any other, so pull overwrote the edited config with
# the stored one: "new.txt" is gone from it (asked for, not expected), "test.txt" is still there.
COMMAND='cat .git/gits.sh | has "new.txt" "test.txt"'
EXPECTED_STDOUT="test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull restored the config too"
