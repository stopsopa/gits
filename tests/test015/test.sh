#
# GITS_PULL_TO_SYNC: the clone of the storage is kept in the directory from that variable instead
# of being cloned into a directory with a random name by every command and removed at its end.
#
# What is tested, in this order:
#
#   1. the first command clones into that directory (it is created), nothing is made in the project
#   2. push --yes through it reaches the storage; the directory stays, clean (git status empty)
#   3. the next command doesn't clone, it fetches: a commit made in the storage by "another
#      machine" is seen (diff shows the difference, pull --yes brings it)
#   4. whatever a previous run left there (an untracked file, a local commit which was not pushed)
#      is thrown away before the directory is used
#   5. the value: ~/ is expanded; a relative path is refused; a directory with something else in it
#      (not empty and not a clone; a clone of another repository) is refused and not touched
#   6. state and isinsync work through it too
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test015/test.sh
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
# an empty storage repository in ${WORK}/GITS_SOURCE, goes to ${WORK}, and defines function "test"
# (bash/test.sh) and the helpers used below (gits, has, listing, stored, storage_commits, project, ...)
source "${_DIR}/../_lib.sh"


D="git@github.com:tmp__repo.git"

project repo "git@github.com:tmp/repo.git"
cd repo
echo 'one' > test.txt
cat <<EEE > .git/gits.sh
GITS_TARGETDIR="${D}"
GITS_LIST=(
    "gits.sh::\$GITS_TARGETDIR/gits.sh"
    "../test.txt::\$GITS_TARGETDIR/test.txt"
)
EEE

# only the project itself, ever: no directory with a random name
LISTING=".git test.txt"

# KEEP: the directory of the kept clone. It doesn't exist yet.
KEEP="${WORK}/keep/clone"
export GITS_PULL_TO_SYNC="${KEEP}"

# in the kept clone: is there anything which is not committed? (prints nothing when clean)
function keep_status {
  git -C "${KEEP}" status --porcelain
}

# ---------- the first command clones ----------

COMMAND='gits diff 2>&1 | has "_TARGETGITDIR: ${KEEP} (GITS_PULL_TO_SYNC)" "Cloning into" "gits keeping ${KEEP}" "gits cleaning"; listing'
EXPECTED_STDOUT="_TARGETGITDIR: ${KEEP} (GITS_PULL_TO_SYNC)
Cloning into
gits keeping ${KEEP}
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "first command: clones into the directory, nothing in the project"

# ---------- push through the kept clone ----------

COMMAND='gits push --yes > /dev/null 2>&1; stored "${D}/test.txt"; storage_commits; keep_status; listing'
EXPECTED_STDOUT="one
1
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes: stored, the kept clone is clean"

# the second run doesn't clone any more
COMMAND='gits diff 2>&1 | has "Cloning into" "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second command: no clone, in sync"

# ---------- a change made somewhere else is fetched ----------

# "another machine": a commit made directly in the storage
echo 'two' > "${GITS_SOURCE}/${D}/test.txt"
git -C "${GITS_SOURCE}" commit -q -a -m "from another machine"

COMMAND='gits isinsync; echo "code ${?}"; gits pull --yes > /dev/null 2>&1; cat test.txt; keep_status'
EXPECTED_STDOUT="code 1
two"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a commit from another machine is fetched: isinsync 1, pull brings it"

# ---------- leftovers of a previous run ----------

# an untracked file and a commit which never reached the storage
echo 'left' > "${KEEP}/leftover.txt"
echo 'local' > "${KEEP}/${D}/test.txt"
git -C "${KEEP}" commit -q -a -m "never pushed"

COMMAND='gits diff 2>&1 | has "files are in sync"; listing "${KEEP}"; cat "${KEEP}/${D}/test.txt"; git -C "${KEEP}" log --format=%s -1; storage_commits'
EXPECTED_STDOUT="files are in sync
.git ${D}
two
from another machine
2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "leftovers (untracked file, local commit) are thrown away"

# ---------- state ----------

COMMAND='cd "${WORK}" && gits state 2>&1 | has "all in sync" "gits keeping ${KEEP}"; listing "${WORK}/repo"'
EXPECTED_STDOUT="gits keeping ${KEEP}
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state uses it too"

# ---------- the value ----------

# ~/ is the home directory (${HOME} of the test): a second, fresh clone there
COMMAND='GITS_PULL_TO_SYNC="~/kept" gits diff 2>&1 | has "Cloning into" "files are in sync"; listing "${HOME}/kept"'
EXPECTED_STDOUT="Cloning into
files are in sync
.git ${D}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "~/ is expanded"

# a relative path would be another directory for every project
COMMAND='GITS_PULL_TO_SYNC="some/dir" gits diff 2>&1 | has "has to be an absolute path or start with ~/"; listing'
EXPECTED_STDOUT="has to be an absolute path or start with ~/
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a relative path is refused"

# a directory with something in it which is not a clone: refused, and still there afterwards
mkdir -p "${WORK}/mine"
echo 'important' > "${WORK}/mine/file.txt"
COMMAND='GITS_PULL_TO_SYNC="${WORK}/mine" gits diff 2>&1 | has "is not empty and not a clone of the storage"; listing "${WORK}/mine"'
EXPECTED_STDOUT="is not empty and not a clone of the storage
file.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a directory with other content is refused and not touched"

# a clone of another repository: refused, its untracked file stays (nothing was cleaned there)
storage "${WORK}/other"
git clone -q "${WORK}/other" "${WORK}/otherclone" 2> /dev/null
echo 'important' > "${WORK}/otherclone/file.txt"
COMMAND='GITS_PULL_TO_SYNC="${WORK}/otherclone" gits isinsync 2>&1 | has "not of the storage"; echo "code ${PIPESTATUS[0]}"; listing "${WORK}/otherclone"'
EXPECTED_STDOUT="not of the storage
code 2
.git file.txt ${D}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a clone of another repository is refused and not touched"
