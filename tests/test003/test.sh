#
# The other direction: a second clone of the same project (another machine) gets everything back
# with "gits init" + "gits pull --yes".
#
# /bin/bash tests/test003/test.sh
# /bin/bash test.sh test003
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

project one "git@github.com:tmp/repo.git"
cd one
echo 'test file' > test.txt
echo 'xx config' > .git/xx.ts
mkdir -p "${HOME}/.config/app"
echo 'from home' > "${HOME}/.config/app/h.conf"
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
mkdir -p deep/dir
echo 'deep' > deep/dir/file.txt
gits push --yes > /dev/null 2>&1 || fail "push from the first machine failed"
cd ..

# "another machine": the same remote, nothing else, also nothing in home
rm -rf "${HOME}/.config"
project two "git@github.com:tmp/repo.git"
cd two

# ---------- init restores the config from the storage ----------

COMMAND='gits init 2>&1 | has ".git/gits.sh restored from the storage: ${D}/gits.sh"'
EXPECTED_STDOUT=".git/gits.sh restored from the storage: ${D}/gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init restores the config from the storage"

COMMAND='diff .git/gits.sh ../one/.git/gits.sh && listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "restored config is the one of the first machine, nothing else was created"

# ---------- pull ----------

COMMAND='gits pull 2>&1 | has "If you are sure that you want to pull them: gits pull --yes"'
EXPECTED_STDOUT="If you are sure that you want to pull them: gits pull --yes"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "pull without --yes"

COMMAND='listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull without --yes: nothing is written"

COMMAND='gits pull --yes 2>&1 | has "'"'"'${D}/test.txt'"'"' -> '"'"'../test.txt'"'"'" "files pulled"'
EXPECTED_STDOUT="'${D}/test.txt' -> '../test.txt'
files pulled"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull --yes: what is copied"

COMMAND='cat test.txt .git/xx.ts deep/dir/file.txt "${HOME}/.config/app/h.conf" && listing'
EXPECTED_STDOUT="test file
xx config
deep
from home
.git deep test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pulled files: plain, in .git, in a new directory, in home (directories created)"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync after pull"

COMMAND='gits pull > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull without --yes, in sync"

# ---------- a change made on the first machine arrives on the second one ----------

cd ../one
echo 'changed on one' > test.txt
gits push --yes > /dev/null 2>&1 || fail "second push from the first machine failed"
cd ../two

COMMAND='gits diff 2>&1 | has "-changed on one" "+test file"'
EXPECTED_STDOUT="-changed on one
+test file"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff sees the change of the other machine: what is stored, what is here"

COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat test.txt'
EXPECTED_STDOUT="0
changed on one"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second pull"

# local files are overwritten, that is what pull is for
echo 'local edit' > test.txt

COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat test.txt'
EXPECTED_STDOUT="0
changed on one"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull overwrites local edits"

# ---------- an element the storage knows nothing about ----------

cat <<EEE >> .git/gits.sh
GITSTORAGELIST+=("../new.txt::\$GITSTORAGETARGETDIR/new.txt")
EEE

COMMAND='gits pull --yes 2>&1 | has "file '"'"'${D}/new.txt'"'"' doesn'"'"'t exist in the storage"'
EXPECTED_STDOUT="file '${D}/new.txt' doesn't exist in the storage"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull with an element missing in the storage"

COMMAND='listing'
EXPECTED_STDOUT=".git deep test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created for it"

# the config is in the list: pull brought the stored one back
COMMAND='cat .git/gits.sh | has "new.txt" "test.txt"'
EXPECTED_STDOUT="test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull restored the config too"
