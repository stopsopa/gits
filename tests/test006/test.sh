#
# gits add: registers files in .git/gits.sh and does nothing else.
#
# /bin/bash tests/test006/test.sh
# /bin/bash test.sh test006
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

COMMAND='gits add file.txt 2>&1 | has "doesn'"'"'t exist, create it with: gits init"'
EXPECTED_STDOUT="doesn't exist, create it with: gits init"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add without config"

cat <<EEE > .git/gits.sh
#!/bin/bash

GITSTORAGETARGETDIR="${D}"

# list
GITSTORAGELIST=(
  "gits.sh::\${GITSTORAGETARGETDIR}/gits.sh"

  # keep me
  "../.env::\${GITSTORAGETARGETDIR}/.env"
)

echo "after the list"
EEE

echo "E=1" > .env
echo "xx" > .git/xx.ts
mkdir -p "dir/sub dir" dir/node_modules/pkg dir/.git
echo "a" > dir/a.txt
echo "b" > "dir/sub dir/b c.txt"
echo "ignored" > dir/node_modules/pkg/index.js
echo "ignored" > dir/.git/config
echo "z" > "${HOME}/.zshrc"
mkdir -p "${WORK}/elsewhere"
echo "e" > "${WORK}/elsewhere/e.txt"

# ---------- wrong arguments ----------

COMMAND='gits add 2>&1 | has "usage: gits add"'
EXPECTED_STDOUT="usage: gits add"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add without path"

COMMAND='gits add nothing.txt 2>&1 | has ">nothing.txt< is neither a file nor a directory"'
EXPECTED_STDOUT=">nothing.txt< is neither a file nor a directory"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add of a path which doesn't exist"

# ---------- already there (the same file, written another way) ----------

BEFORE="$(cat .git/gits.sh)"

COMMAND='gits add ./.env 2>&1 | has "nothing added"; cat .git/gits.sh'
EXPECTED_STDOUT="nothing added
${BEFORE}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add of a registered file changes nothing"

# ---------- a directory, a file in .git, a file in home, a file elsewhere, all in one call ----------

COMMAND='gits add dir .git/xx.ts ~/.zshrc "${WORK}/elsewhere/e.txt" 2>&1 | has "added lines: 5" "only the config was changed"'
EXPECTED_STDOUT="added lines: 5
only the config was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add: number of lines, reminder"

# indentation and \${...} form are the ones the config already uses; ${WORK:1} = path without the first /
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="#!/bin/bash

GITSTORAGETARGETDIR=\"${D}\"

# list
GITSTORAGELIST=(
  \"gits.sh::\${GITSTORAGETARGETDIR}/gits.sh\"

  # keep me
  \"../.env::\${GITSTORAGETARGETDIR}/.env\"
  \"../dir/a.txt::\${GITSTORAGETARGETDIR}/dir/a.txt\"
  \"../dir/sub dir/b c.txt::\${GITSTORAGETARGETDIR}/dir/sub dir/b c.txt\"
  \"xx.ts::\${GITSTORAGETARGETDIR}/xx.ts\"
  \"~/.zshrc::\${GITSTORAGETARGETDIR}/.zshrc\"
  \"${WORK}/elsewhere/e.txt::\${GITSTORAGETARGETDIR}/${WORK:1}/elsewhere/e.txt\"
)

echo \"after the list\""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "config after add"

COMMAND='storage_commits; listing'
EXPECTED_STDOUT="0
.env .git dir"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add doesn't push and creates nothing"

COMMAND='gits add dir 2>&1 | has "nothing added: all 2 file(s) are already"'
EXPECTED_STDOUT="nothing added: all 2 file(s) are already"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second add of the same directory"

# ---------- the result is a working config ----------

COMMAND='gits push --yes 2>&1 | has "after the list"'
EXPECTED_STDOUT="after the list"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the config made by add, output of the config is shown"

COMMAND='stored "${D}/dir/sub dir/b c.txt"; stored "${D}/.zshrc"; stored "${D}/${WORK:1}/elsewhere/e.txt"'
EXPECTED_STDOUT="b
z
e"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored files: with spaces, from home, from elsewhere"

# ---------- -e: registered as encrypted ----------

echo "secret" > secret.txt

F1="  \"../secret.txt:e:\${GITSTORAGETARGETDIR}/secret.txt\"
)"

COMMAND='gits add -e secret.txt > /dev/null 2>&1; echo "${?}"; cat .git/gits.sh | has "${F1}"'
EXPECTED_STDOUT="0
${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add -e"

# ---------- a config with the other style and an empty list ----------

cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"
GITSTORAGELIST=(
)
EEE

COMMAND='gits add .env > /dev/null 2>&1; cat .git/gits.sh'
EXPECTED_STDOUT="GITSTORAGETARGETDIR=\"${D}\"
GITSTORAGELIST=(
    \"../.env::\$GITSTORAGETARGETDIR/.env\"
)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add to an empty list: default style"

# ---------- a config add can't understand is left as it was ----------

echo 'GITSTORAGELIST=("a::b")' > .git/gits.sh

COMMAND='gits add .env 2>&1 | has "can'"'"'t find the end of GITSTORAGELIST"'
EXPECTED_STDOUT="can't find the end of GITSTORAGELIST"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add to a config in one line"

COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT='GITSTORAGELIST=("a::b")'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add to a config in one line changes nothing"
