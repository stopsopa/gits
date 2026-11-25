#
# gits find and gits state: the commands which work with ALL projects below the current directory,
# not with one.
#
# A small "workspace" (${WORK}/ws) is built with projects in different states and with things
# which must not be taken for a project.
#
# What is tested, in this order:
#
#   1. an empty directory: state says "nothing found", find prints nothing, both end with 0
#   2. find lists the directories of the projects: at any depth, also one with the config of the
#      original tool (.git/gitstorage-config.sh); not in node_modules, not through a symlink, not
#      where .git is a file, not a gits.sh outside of .git. Inside of a project it prints "."
#   3. state with one project in sync, one edited, one with a missing source file and one with the
#      old config: exit code 1, and its output has
#        - a header for every project, numbered "n : all"
#        - the two lines to paste to another terminal (cd "<project>" + gits diff)
#        - one clone of the storage, reused for all projects
#        - git status of the project which differs, the error for the missing file
#        - the migration of the old config, the counts of projects in sync / not in sync
#      and state changes nothing: no temporary directory left, local files and the storage untouched
#   4. everything fixed: state ends with 0 and counts 4 projects in sync
#   5. a project with a broken config is counted as an error, the other projects are still checked
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test004/test.sh
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

# The workspace: an empty directory, state and find are executed in it.
mkdir ws
cd ws
# WS: absolute path of the workspace, used in expected messages.
# LOG: file where the long output of one "gits state" is kept, several checks below read it.
WS="${WORK}/ws"
LOG="${WORK}/state.log"

# ---------- nothing found ----------

# No project below the current directory: state says "nothing found". Not an error, exit code 0.
COMMAND='gits state 2>&1 | has "nothing found"'
EXPECTED_STDOUT="nothing found"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state, nothing found"

# find in the same empty directory: prints nothing at all, exit code 0
COMMAND='gits find'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find, nothing found"

# ---------- projects ----------

# make <directory> <name of the repository> [name of the config file]
# Creates a project in <directory> with remote origin git@github.com:tmp/<name>.git, one file
# (file.txt) and a config which lists the config itself and that file.
# The third argument makes the config under another name (used for the config of the original tool).
function make {
  local NAME="${3:-gits.sh}"
  project "${1}" "git@github.com:tmp/${2}.git"
  echo "content of ${2}" > "${1}/file.txt"
  cat <<EEE > "${1}/.git/${NAME}"
GITS_TARGETDIR="git@github.com:tmp__${2}.git"
GITS_LIST=(
    "${NAME}::\$GITS_TARGETDIR/${NAME}"
    "../file.txt::\$GITS_TARGETDIR/file.txt"
)
EEE
}

# push <directory>
# "gits push --yes" in that project, quietly. Preparation, not a check: when it fails the test stops.
function push {
  (cd "${1}" && gits push --yes > /dev/null 2>&1) || fail "push in >${1}< failed"
}

# Project "a": pushed and not touched afterwards. The one which is in sync.
make a a
push a

# Project "b", one directory deeper: pushed and then edited locally. The one which differs.
make b/b b
push b/b
echo "edited" > b/b/file.txt

# Project "c": pushed and then its file is removed. The one with a missing source file.
make c c
push c
rm c/file.txt

# Project "legacy": has only the config of the original tool (.git/gitstorage-config.sh) and was
# never pushed. It has to be found too, and state migrates it to .git/gits.sh on the way.
make legacy legacy gitstorage-config.sh

# Two real projects inside of node_modules directories (one at the top, one inside project "a"):
# node_modules is never entered, so they must not be found.
make node_modules/pkg pkg
make a/node_modules/pkg pkg2

# Three things which are not projects:
#   plain/sub/gits.sh   a file with the right name but not in .git
#   link-to-a           a symlink to project "a": symlinks are not followed (it would be found twice)
mkdir -p plain/sub
echo "x" > plain/sub/gits.sh
ln -s a link-to-a

#   worktree/.git       .git which is a file, not a directory (that is how a worktree or
#                       a submodule looks): there is no .git/gits.sh in it
mkdir worktree
echo "gitdir: ../a/.git" > worktree/.git

# The names in the workspace. After every command the listing has to be exactly this:
# one name more would be a temporary clone which was not removed.
LISTING="a b c legacy link-to-a node_modules plain worktree"

# ---------- find ----------

# find prints the directory of every project, one per line, sorted, relative to the current
# directory: a, b/b (found one directory deeper), c and legacy (found by its old config).
# Nothing from node_modules, no link-to-a, no plain, no worktree.
COMMAND='gits find'
EXPECTED_STDOUT="./a
./b/b
./c
./legacy"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find"

# Executed inside of project "a": the project of the current directory is printed as ".".
# (a/node_modules/pkg is below it and still not found.)
COMMAND='cd a && gits find'
EXPECTED_STDOUT="."
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "find in a project: the project in the current directory is '.'"

# ---------- state ----------

# state for the whole workspace. Its output (stdout and stderr together) goes to ${LOG} for the
# checks below, here only the exit code: 1, because not every project is in sync.
COMMAND='gits state > "${LOG}" 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state: exit code when something is not in sync"

# Every project starts in the output with a header: the line of ">", the number of the project,
# the number of all projects and the path of its config. Four projects were found, in the order
# of find; the fourth is shown with the old name of its config, because that is what was found.
MARK=">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"

H1="${MARK} 1 : 4 >./a/.git/gits.sh<"
H2="${MARK} 2 : 4 >./b/b/.git/gits.sh<"
H3="${MARK} 3 : 4 >./c/.git/gits.sh<"
H4="${MARK} 4 : 4 >./legacy/.git/gitstorage-config.sh<"

# all four headers are in the output
COMMAND='cat "${LOG}" | has "${H1}" "${H2}" "${H3}" "${H4}"'
EXPECTED_STDOUT="${H1}
${H2}
${H3}
${H4}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: headers, the last one is a config of the original tool"

# For a project which is not in sync state prints two lines ready to paste to another terminal:
# cd "<absolute path of the project>" and "gits diff". Here for b/b, with the empty lines around them.
PASTE="
  cd \"${WS}/b/b\"
  gits diff
"

# The block is in the output. "has" prints the fragment as it is, with its empty first line.
COMMAND='cat "${LOG}" | has "${PASTE}"'
# the library compares the output without the new lines at its end
EXPECTED_STDOUT="
  cd \"${WS}/b/b\"
  gits diff"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: the two lines which are pasted to another terminal"

# Ten fragments of the same output:
#   F1   the storage is cloned to a directory inside the current one (random name follows)
#   F2   the clone is made when the first project needs it ...
#   F3   ... and reused for the next ones ("already exist")
#   F4   git status of the project which differs, executed in the root of the clone (path with the
#        directory of the project)
#   F5   the missing file.txt of project "c", with its absolute path
#   F6   the verdict for project "c"
#   F7   the old config of project "legacy" was renamed to gits.sh
#   F8   in sync: 1 project (a)
#   F9   not in sync or failed: 3 projects (b/b, c, legacy)
#   F10  the temporary clone is removed at the end
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

# all ten are there
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

# Two fragments which must NOT be in the output, so nothing is expected:
# the file of project "a" in any git status (a is in sync), and anything about node_modules.
COMMAND='cat "${LOG}" | has "tmp__a.git/file.txt" "node_modules"'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: what should not be in the output"

# "Cloning into" is printed by git clone: exactly once for four projects.
COMMAND='grep -c "^Cloning into" "${LOG}"'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: storage cloned once"

# Only the headers and the verdicts, in the order they were printed (the ">" in front of the headers
# removed by sed): every project is followed by its own verdict. "legacy" is not in sync because
# it was never pushed.
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

# the workspace has the same names as before state: no temporary clone left
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state leaves nothing behind"

# The .git of "legacy" has the same names as the .git of "a" (expected value is computed from a):
# gits.sh is there, gitstorage-config.sh is gone and nothing else was added.
COMMAND='listing legacy/.git'
EXPECTED_STDOUT="$(listing a/.git)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "legacy project has gits.sh and nothing more than the others"

# state only looks: the local edit in b/b is still there (it was not overwritten by the stored
# file) and the storage still has the 3 commits of the three pushes above.
COMMAND='cat b/b/file.txt; storage_commits'
EXPECTED_STDOUT="edited
3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state changes neither local files nor the storage"

# ---------- everything fixed ----------

# Every problem is fixed: the edit of b/b is pushed, file.txt of "c" is written again with its
# stored content, and "legacy" is pushed for the first time (with its migrated config).
push b/b
echo "content of c" > c/file.txt
push legacy

# the header of the fourth project now shows the new name of the config
H4="${MARK} 4 : 4 >./legacy/.git/gits.sh<"

# state again: exit code 0, all 4 projects in sync, 0 errors.
COMMAND='gits state 2>&1 | has "${H4}" "COUNT_SUCCESS : 4" "COUNT_ERROR   : 0"'
EXPECTED_STDOUT="${H4}
COUNT_SUCCESS : 4
COUNT_ERROR   : 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state, all in sync: migrated project under its new name, counts"

# ---------- a broken config doesn't hide the other projects ----------

# The config of project "c" is replaced by a script which ends the shell: gits can't read
# GITS_TARGETDIR and GITS_LIST from it.
echo 'exit 0' > c/.git/gits.sh

# state reports the broken config ("didn't run to its end"), counts it as 1 error and still checks
# the other three projects (3 in sync). Exit code 1.
COMMAND='gits state 2>&1 | has "didn'"'"'t run to its end" "COUNT_SUCCESS : 3" "COUNT_ERROR   : 1"'
EXPECTED_STDOUT="didn't run to its end
COUNT_SUCCESS : 3
COUNT_ERROR   : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state with a broken config: the rest is checked"

# also after the run with a broken config nothing was left in the workspace
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing left behind at the end"
