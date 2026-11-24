#
# The main path on one machine: gits init, diff, isinsync, push.
#
# /bin/bash tests/test002/test.sh
# /bin/bash test.sh test002
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

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

source "${_DIR}/../_lib.sh"

D="git@github.com:tmp__repo.git"

project repo "git@github.com:tmp/repo.git"
cd repo

echo 'test file' > test.txt
echo 'with space' > "with space.txt"
echo 'xx config' > .git/xx.ts
mkdir -p "${HOME}/.config"
echo 'from home' > "${HOME}/.config/h.conf"

LISTING=".git test.txt with space.txt"

# ---------- init: nothing in the storage for this project, the built-in template is used ----------

COMMAND='gits init 2>&1 | has ".git/gits.sh generated (built-in template)"'
EXPECTED_STDOUT=".git/gits.sh generated (built-in template)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init"

F1="GITSTORAGETARGETDIR=\"${D}\""
F2="# used in git@github.com:tmp/repo.git"
F3='"gits.sh::$GITSTORAGETARGETDIR/gits.sh"'

COMMAND='cat .git/gits.sh | has "${F1}" "${F2}" "${F3}"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init: GITSTORAGETARGETDIR made from remote origin, remote in the comment, the config stores itself"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after init"

GENERATED="$(cat .git/gits.sh)"

COMMAND='gits init 2>&1 | has "is already present - initialization not needed"'
EXPECTED_STDOUT="is already present - initialization not needed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second init"

COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="${GENERATED}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second init changes nothing"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "the generated config works as it is: not in sync, the storage is empty"

cat <<EEE > .git/gits.sh
#!/bin/bash

GITSTORAGETARGETDIR="${D}"

GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
    "xx.ts::\${GITSTORAGETARGETDIR}/xx.ts"
    "../test.txt::\$GITSTORAGETARGETDIR/test.txt"

    # comment between elements
    "../with space.txt::\$GITSTORAGETARGETDIR/sub dir/with space.txt"
    "~/.config/h.conf::\$GITSTORAGETARGETDIR/home/h.conf"
)
EEE

# ---------- diff: everything is new for the storage ----------

COMMAND='gits diff 2>&1 | has "_TARGETGITDIR: ${WORK}/repo/" "files are not in sync" "+test file" "+from home" "final url ${GITSTORAGESOURCE} (directory ${D})" "gits cleaning ${WORK}/repo/"'
EXPECTED_STDOUT="_TARGETGITDIR: ${WORK}/repo/
files are not in sync
+test file
+from home
final url ${GITSTORAGESOURCE} (directory ${D})
gits cleaning ${WORK}/repo/"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "first diff: temporary directory in pwd, content of new files in the diff, url, cleaning"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after diff"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync, not in sync: prints nothing"

# ---------- push ----------

COMMAND='gits push 2>&1 | has "nothing was changed. If you are sure that you want to push them: gits push --yes"'
EXPECTED_STDOUT="nothing was changed. If you are sure that you want to push them: gits push --yes"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "push without --yes"

COMMAND='storage_commits'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push without --yes: storage untouched"

COMMAND='gits push --yes 2>&1 | has "'"'"'../test.txt'"'"' -> '"'"'${D}/test.txt'"'"'" "files pushed"'
EXPECTED_STDOUT="'../test.txt' -> '${D}/test.txt'
files pushed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes: what is copied"

COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes: one commit"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after push"

COMMAND='stored "${D}/test.txt"; stored "${D}/xx.ts"; stored "${D}/sub dir/with space.txt"; stored "${D}/home/h.conf"'
EXPECTED_STDOUT="test file
xx config
with space
from home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored files: plain, from .git, with spaces, from home"

COMMAND='stored "${D}/gits.sh"'
EXPECTED_STDOUT="$(cat .git/gits.sh)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored config"

COMMAND='storage "${WORK}/look" && git -C "${WORK}/look" log -1 --format=%s && listing "${WORK}/look"'
EXPECTED_STDOUT="gits push ${D}
.git ${D}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "commit message, nothing else in the storage"

# ---------- in sync ----------

COMMAND='gits diff 2>&1 | has "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff in sync"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync, in sync: prints nothing"

COMMAND='gits push > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push without --yes, in sync"

COMMAND='gits push --yes 2>&1 | has "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes, in sync"

COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes, in sync: no new commit"

# ---------- a change ----------

echo 'changed' > test.txt

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync after a change"

# git status is shown from the directory of the project; files which didn't change are not there
COMMAND='gits diff 2>&1 | has "-test file" "+changed" "modified:   test.txt" "xx config"'
EXPECTED_STDOUT="-test file
+changed
modified:   test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after a change: what is stored, what is here, git status"

# ---------- a source file which doesn't exist ----------

mv .git/xx.ts "${WORK}/xx.ts"

COMMAND='gits diff 2>&1 | has "source file '"'"'${WORK}/repo/.git/xx.ts'"'"' doesn'"'"'t exist" "files are not in sync - at least one source file is missing"'
EXPECTED_STDOUT="source file '${WORK}/repo/.git/xx.ts' doesn't exist
files are not in sync - at least one source file is missing"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "missing source: diff"

COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "missing source: isinsync"

# push with a missing source: the rest is stored, the problem is not silent
COMMAND='gits push --yes 2>&1 | has "files pushed"'
EXPECTED_STDOUT="files pushed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "push with missing source"

COMMAND='storage_commits; stored "${D}/test.txt"; stored "${D}/xx.ts"'
EXPECTED_STDOUT="2
changed
xx config"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with missing source: commit, the rest is stored, file of the missing source stays in the storage"

mv "${WORK}/xx.ts" .git/xx.ts

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync again"

# ---------- storage which can't be cloned: error, and the temporary directory is gone ----------

COMMAND='GITSTORAGESOURCE="${WORK}/nothing-here" gits diff 2>&1 | has "can'"'"'t clone storage GITSTORAGESOURCE=>${WORK}/nothing-here<"'
EXPECTED_STDOUT="can't clone storage GITSTORAGESOURCE=>${WORK}/nothing-here<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "storage not reachable: diff"

COMMAND='GITSTORAGESOURCE="${WORK}/nothing-here" gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "storage not reachable: isinsync is an error, not 'not in sync'"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after failed clone"

# ---------- targets which could damage the storage are refused ----------

CONFIG="$(cat .git/gits.sh)"

printf 'GITSTORAGETARGETDIR="%s"\nGITSTORAGELIST=(\n  "xx.ts::xx.ts"\n)\n' "${D}" > .git/gits.sh

F1="target file 'xx.ts' should be in a directory, like 'xxx/xx.ts'"
COMMAND='gits push --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "target in the root of the storage"

printf 'GITSTORAGETARGETDIR="%s"\nGITSTORAGELIST=(\n  "xx.ts::$GITSTORAGETARGETDIR/../../xx.ts"\n)\n' "${D}" > .git/gits.sh

F1="must not contain '..'"
COMMAND='gits push --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "target with .."

printf 'GITSTORAGETARGETDIR="%s"\nGITSTORAGELIST=(\n  "xx.ts"\n)\n' "${D}" > .git/gits.sh

F1='is neither "SOURCE::TARGET" nor "SOURCE:e:TARGET"'
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "element without separator"

printf 'GITSTORAGETARGETDIR="%s"\nGITSTORAGELIST=(\n)\n' "${D}" > .git/gits.sh

F1="shouldn't be empty"
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "empty list"

printf 'GITSTORAGELIST=(\n  "xx.ts::d/xx.ts"\n)\n' > .git/gits.sh

F1="doesn't define GITSTORAGETARGETDIR"
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no GITSTORAGETARGETDIR"

echo "${CONFIG}" > .git/gits.sh

COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was pushed by the refused configs, nothing left behind"
