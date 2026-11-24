#
# .git/gitstorage-config.sh -> .git/gits.sh: gits migrate, gits migrate all, and automatically.
#
# /bin/bash tests/test005/test.sh
# /bin/bash test.sh test005
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

# legacy <directory> <name>
function legacy {
  project "${1}" "git@github.com:tmp/${2}.git"
  echo "content" > "${1}/file.txt"
  cat <<EEE > "${1}/.git/gitstorage-config.sh"
#!/bin/bash

# paths will be solved from directory where gitstorage-config.sh is

GITSTORAGETARGETDIR="git@github.com:tmp__${2}.git"

GITSTORAGELIST=(
    "gitstorage-config.sh::\$GITSTORAGETARGETDIR/gitstorage-config.sh"
    "../file.txt::\$GITSTORAGETARGETDIR/file.txt"
    "../../other/.git/gitstorage-config.sh::\$GITSTORAGETARGETDIR/other/gitstorage-config.sh"
)
EEE
  chmod 600 "${1}/.git/gitstorage-config.sh"
}

# only the element of the config itself is changed
EXPECTED_BODY='#!/bin/bash

# paths will be solved from directory where gitstorage-config.sh is

GITSTORAGETARGETDIR="git@github.com:tmp__one.git"

GITSTORAGELIST=(
    "gits.sh::$GITSTORAGETARGETDIR/gits.sh"
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
    "../../other/.git/gitstorage-config.sh::$GITSTORAGETARGETDIR/other/gitstorage-config.sh"
)'

# ---------- gits migrate ----------

legacy one one
cd one

COMMAND='gits migrate 2>&1 | has "migrated ${WORK}/one/.git/gitstorage-config.sh -> ${WORK}/one/.git/gits.sh"'
EXPECTED_STDOUT="migrated ${WORK}/one/.git/gitstorage-config.sh -> ${WORK}/one/.git/gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate"

COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate: only the element of the config itself is changed"

COMMAND='listing .git | has "gits.sh" "gitstorage-config.sh"; stat -c "%a" .git/gits.sh 2> /dev/null || stat -f "%Lp" .git/gits.sh'
EXPECTED_STDOUT="gits.sh
600"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate: old config is removed, permissions are kept"

COMMAND='gits migrate 2>&1 | has "nothing to migrate: .git/gits.sh is already here"; cat .git/gits.sh'
EXPECTED_STDOUT="nothing to migrate: .git/gits.sh is already here
${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate again changes nothing"

# both: nothing is touched, the person has to decide
echo "old" > .git/gitstorage-config.sh

COMMAND='gits migrate 2>&1 | has "compare them and remove the old one by hand"'
EXPECTED_STDOUT="compare them and remove the old one by hand"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate with both configs"

COMMAND='cat .git/gitstorage-config.sh .git/gits.sh'
EXPECTED_STDOUT="old
${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate with both configs: both untouched"

COMMAND='gits diff 2>&1 | has "source file '"'"'${WORK}/other/.git/gitstorage-config.sh'"'"' doesn'"'"'t exist"'
EXPECTED_STDOUT="source file '${WORK}/other/.git/gitstorage-config.sh' doesn't exist"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "with both configs gits.sh is the one in use"

rm .git/gitstorage-config.sh
cd ..

mkdir empty

COMMAND='cd empty && gits migrate 2>&1 | has "nothing to migrate: there is no .git/gitstorage-config.sh in the current directory"'
EXPECTED_STDOUT="nothing to migrate: there is no .git/gitstorage-config.sh in the current directory"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate, nothing there"

COMMAND='gits migrate what 2>&1 | has "usage: gits migrate | gits migrate all"'
EXPECTED_STDOUT="usage: gits migrate | gits migrate all"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate with unknown argument"

# ---------- automatically: any command which needs the config ----------

legacy auto auto
cd auto
rm -f .git/gitstorage-config.sh
cat <<'EEE' > .git/gitstorage-config.sh
GITSTORAGETARGETDIR="git@github.com:tmp__auto.git"
GITSTORAGELIST=(
    "gitstorage-config.sh::${GITSTORAGETARGETDIR}/gitstorage-config.sh"
    "../file.txt::${GITSTORAGETARGETDIR}/file.txt"
)
EEE

F1="migrated ${WORK}/auto/.git/gitstorage-config.sh -> ${WORK}/auto/.git/gits.sh"
F2="'gits.sh' -> 'git@github.com:tmp__auto.git/gits.sh'"

COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}"'
EXPECTED_STDOUT="${F1}
${F2}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the old config: migrated, stored under the new name"

COMMAND='listing .git | has "gits.sh" "gitstorage-config.sh"; storage "${WORK}/look" && listing "${WORK}/look/git@github.com:tmp__auto.git"'
EXPECTED_STDOUT="gits.sh
file.txt gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "automatic migration: old config removed, storage has only the new name"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync after the migration"

cd ..

# isinsync migrates too, without a word
legacy quiet quiet

COMMAND='cd quiet && gits isinsync 2> /dev/null; listing .git | has "gits.sh" "gitstorage-config.sh"'
EXPECTED_STDOUT="gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync with the old config: prints nothing, migrated"

# ---------- all at once ----------

mkdir ws
cd ws
legacy p1 p1
legacy deep/p2 p2
legacy both both
echo "new" > both/.git/gits.sh
project fresh "git@github.com:tmp/fresh.git"
echo 'GITSTORAGETARGETDIR="x"' > fresh/.git/gits.sh
legacy node_modules/p3 p3

F1="migrated ${WORK}/ws/p1/.git/gitstorage-config.sh"
F2="migrated ${WORK}/ws/deep/p2/.git/gitstorage-config.sh"
F3="both >${WORK}/ws/both/.git/gits.sh< and"

# project with the new config only (fresh) is left alone
COMMAND='gits migrate all 2>&1 | has "${F1}" "${F2}" "${F3}" "COUNT_SUCCESS : 2" "COUNT_ERROR   : 1" "fresh"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}
COUNT_SUCCESS : 2
COUNT_ERROR   : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate all with one conflict"

COMMAND='ls p1/.git/gits.sh p1/.git/gitstorage-config.sh deep/p2/.git/gits.sh deep/p2/.git/gitstorage-config.sh node_modules/p3/.git/gits.sh node_modules/p3/.git/gitstorage-config.sh 2> /dev/null; cat both/.git/gits.sh'
EXPECTED_STDOUT="deep/p2/.git/gits.sh
node_modules/p3/.git/gitstorage-config.sh
p1/.git/gits.sh
new"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate all: p1 and deep/p2 migrated, node_modules is not entered, conflict untouched"

rm both/.git/gitstorage-config.sh

COMMAND='gits migrate all 2>&1 | has "nothing found"'
EXPECTED_STDOUT="nothing found"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate all, nothing left"
