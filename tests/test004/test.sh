#
# gits state and gits find: all projects below the current directory.
#
# /bin/bash tests/test004/test.sh
# /bin/bash test.sh test004
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

mkdir ws
cd ws
WS="${WORK}/ws"
LOG="${WORK}/state.log"

# ---------- nothing found ----------

COMMAND='gits state 2>&1 | has "nothing found"'
EXPECTED_STDOUT="nothing found"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state, nothing found"

COMMAND='gits find'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find, nothing found"

# ---------- projects ----------

# make <directory> <name of the repository> [name of the config file]
function make {
  local NAME="${3:-gits.sh}"
  project "${1}" "git@github.com:tmp/${2}.git"
  echo "content of ${2}" > "${1}/file.txt"
  cat <<EEE > "${1}/.git/${NAME}"
GITSTORAGETARGETDIR="git@github.com:tmp__${2}.git"
GITSTORAGELIST=(
    "${NAME}::\$GITSTORAGETARGETDIR/${NAME}"
    "../file.txt::\$GITSTORAGETARGETDIR/file.txt"
)
EEE
}

# push <directory>
function push {
  (cd "${1}" && gits push --yes > /dev/null 2>&1) || fail "push in >${1}< failed"
}

make a a
push a

make b/b b
push b/b
echo "edited" > b/b/file.txt

make c c
push c
rm c/file.txt

# config of the original tool: found too, and migrated on the way
make legacy legacy gitstorage-config.sh

# never entered
make node_modules/pkg pkg
make a/node_modules/pkg pkg2

# a directory without a config, a config outside of .git, and a symlink to a project
mkdir -p plain/sub
echo "x" > plain/sub/gits.sh
ln -s a link-to-a

# a .git which is a file (worktree, submodule) is not a project
mkdir worktree
echo "gitdir: ../a/.git" > worktree/.git

LISTING="a b c legacy link-to-a node_modules plain worktree"

# ---------- find ----------

COMMAND='gits find'
EXPECTED_STDOUT="./a
./b/b
./c
./legacy"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find"

COMMAND='cd a && gits find'
EXPECTED_STDOUT="."
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find in a project: the project in the current directory is '.'"

# ---------- state ----------

COMMAND='gits state > "${LOG}" 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state: exit code when something is not in sync"

MARK=">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

H1="${MARK} 1 : 4 >./a/.git/gits.sh<"
H2="${MARK} 2 : 4 >./b/b/.git/gits.sh<"
H3="${MARK} 3 : 4 >./c/.git/gits.sh<"
H4="${MARK} 4 : 4 >./legacy/.git/gitstorage-config.sh<"

COMMAND='cat "${LOG}" | has "${H1}" "${H2}" "${H3}" "${H4}"'
EXPECTED_STDOUT="${H1}
${H2}
${H3}
${H4}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: headers, the last one is a config of the original tool"

PASTE="
  cd \"${WS}/b/b\"
  gits diff
"

COMMAND='cat "${LOG}" | has "${PASTE}"'
# the library compares the output without the new lines at its end
EXPECTED_STDOUT="
  cd \"${WS}/b/b\"
  gits diff"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: the two lines which are pasted to another terminal"

F1="_TARGETGITDIR: ${WS}/"
F2="' for './a/.git/gits.sh'"
F3="for './b/b/.git/gits.sh' already exist"
F4="modified:   git@github.com:tmp__b.git/file.txt"
F5="source file '${WS}/c/file.txt' doesn't exist"
F6="files are not in sync - at least one source file is missing"
F7="migrated ${WS}/legacy/.git/gitstorage-config.sh -> ${WS}/legacy/.git/gits.sh"
F8="COUNT_SUCCESS : 1"
F9="COUNT_ERROR   : 3"
F10="gits cleaning ${WS}/"

COMMAND='cat "${LOG}" | has "${F1}" "${F2}" "${F3}" "${F4}" "${F5}" "${F6}" "${F7}" "${F8}" "${F9}" "${F10}"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}
${F4}
${F5}
${F6}
${F7}
${F8}
${F9}
${F10}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: temporary directory in pwd, clone made once and reused, git status, missing source, migration, counts, cleaning"

# project in sync is not listed in any status, node_modules is not entered
COMMAND='cat "${LOG}" | has "tmp__a.git/file.txt" "node_modules"'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: what should not be in the output"

COMMAND='grep -c "^Cloning into" "${LOG}"'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: storage cloned once"

COMMAND='grep -E "^${MARK}|^    files are" "${LOG}" | sed -E "s/^>+ //"'
EXPECTED_STDOUT="1 : 4 >./a/.git/gits.sh<
    files are in sync
2 : 4 >./b/b/.git/gits.sh<
    files are not in sync
3 : 4 >./c/.git/gits.sh<
    files are not in sync - at least one source file is missing
4 : 4 >./legacy/.git/gitstorage-config.sh<
    files are not in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: every header is followed by its own result, in the order of the projects"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state leaves nothing behind"

COMMAND='listing legacy/.git'
EXPECTED_STDOUT="$(listing a/.git)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "legacy project has gits.sh and nothing more than the others"

COMMAND='cat b/b/file.txt; storage_commits'
EXPECTED_STDOUT="edited
3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state changes neither local files nor the storage"

# ---------- everything fixed ----------

push b/b
echo "content of c" > c/file.txt
push legacy

H4="${MARK} 4 : 4 >./legacy/.git/gits.sh<"

COMMAND='gits state 2>&1 | has "${H4}" "COUNT_SUCCESS : 4" "COUNT_ERROR   : 0"'
EXPECTED_STDOUT="${H4}
COUNT_SUCCESS : 4
COUNT_ERROR   : 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state, all in sync: migrated project under its new name, counts"

# ---------- a broken config doesn't hide the other projects ----------

echo 'exit 0' > c/.git/gits.sh

COMMAND='gits state 2>&1 | has "didn'"'"'t run to its end" "COUNT_SUCCESS : 3" "COUNT_ERROR   : 1"'
EXPECTED_STDOUT="didn't run to its end
COUNT_SUCCESS : 3
COUNT_ERROR   : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state with a broken config: the rest is checked"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing left behind at the end"
