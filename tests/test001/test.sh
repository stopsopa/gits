#
# What gits does before any project is involved: the help, the version, wrong arguments,
# and the env var GITS_SOURCE which every command (except --help and --version) requires.
#
# What is tested, in this order:
#
#   1. --help with everything defined: the commands and --update are listed, the table of env vars
#      shows the value found in env, nothing is marked as missing
#   2. the table of env vars: for GITS_SHELL the default (/bin/bash) is the value in use when
#      the variable is not defined, and the value from env wins when it is defined
#   3. gits without arguments prints the same as gits --help
#   4. GITS_SOURCE not defined, and defined but empty (both mean the same):
#        - --help still works (exit code 0) but marks the variable as MISSING and explains it
#        - --version still works
#        - every command of gits ends with exit code 1 and says that the variable is not defined
#        - none of that created anything on the disk
#   5. an unknown command and an unsupported flag: exit code 1 and a message
#   6. commands which need a project, executed in a directory which is not one (no .git/gits.sh):
#      exit code 1 and the hint to run "gits init"; for isinsync it is exit code 2 (an error)
#   7. at the end still nothing was created
#
# Needs: the compiled binary (/bin/bash compile.sh). No project and no socket are used here.
#
# /bin/bash tests/test001/test.sh
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

# The storage prepared by tests/_lib.sh. Remembered, because GITS_SOURCE is unset and emptied
# below and has to be put back afterwards.
STORAGE="${GITS_SOURCE}"

# ---------- help with everything defined ----------

# The help page with GITS_SOURCE defined. "has" prints only those of the given fragments which
# are in the output:
#   "gits state"               the list of commands is there
#   "gits --update --check"    the update is described
#   "variable"                 header of the table of env vars
#   GITS_SOURCE="..."          the row of the variable shows the value it has in the shell
#   "MISSING"                  must NOT be there (so it is not in EXPECTED_STDOUT): nothing required is missing
COMMAND='gits --help 2>&1 | has "gits state" "gits --update --check" "variable, and its value in the shell" "GITS_SOURCE=\"${STORAGE}\"" "MISSING"'
EXPECTED_STDOUT="gits state
gits --update --check
variable, and its value in the shell
GITS_SOURCE=\"${STORAGE}\""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: commands, update, table of env vars, value found in env, nothing is missing"

# Only the row of GITS_SHELL from the table, with runs of spaces squeezed to one (tr -s),
# so the padding of the columns doesn't matter.
# Columns: variable with its value in the shell | default | used.
# The variable is not defined here: "(not defined)", and the default /bin/bash is the value in use.
COMMAND='gits --help 2>&1 | grep "^  GITS_SHELL[ =].* | " | tr -s " "'
EXPECTED_STDOUT=" GITS_SHELL (not defined) | /bin/bash | /bin/bash"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: default value wins when env var is not defined"

# The same row with the variable defined for this one call: the value from env is shown next
# to the name and it is the one in use (last column), the default stays /bin/bash.
COMMAND='GITS_SHELL=/bin/zsh gits --help 2>&1 | grep "^  GITS_SHELL[ =].* | " | tr -s " "'
EXPECTED_STDOUT=" GITS_SHELL=\"/bin/zsh\" | /bin/bash | /bin/zsh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: the value which wins is the one from env"

# Defined as an empty text is not the same as not defined, and the first column shows which one
# it is: NAME="" (empty). For gits an empty value counts as no value: the default is used.
COMMAND='GITS_SHELL="" gits --help 2>&1 | grep "^  GITS_SHELL[ =].* | " | tr -s " "'
EXPECTED_STDOUT=" GITS_SHELL=\"\" (empty) | /bin/bash | /bin/bash"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: an empty value is shown as empty, the default is used"

# The table lists every variable gits reacts to, not only the main ones. One row of each kind
# (tr squeezes the padding):
#   - a variable of a lifecycle event, defined here: its script is the value in use, ~/ expanded
#   - the same kind, not defined: no script
#   - a replaceable event: its default is the built-in script
#   - a name from before the rename, not defined
#   - NO_COLOR, a variable of other programs: defined (also as an empty text) means no colors
COMMAND='GITS_PUSH_AFTER_PUSH="~/after.sh" NO_COLOR="" gits --help 2>&1 | grep "^  GITS_PUSH_AFTER_PUSH=\|^  GITS_PUSH_BEFORE_PUSH \|^  GITS_STATE_FIND \|^  GITSTORAGETESHELL \|^  NO_COLOR=" | tr -s " "'
EXPECTED_STDOUT=" GITSTORAGETESHELL (not defined) | (none) | (not used)
 NO_COLOR=\"\" (empty) | (none) | no colors
 GITS_STATE_FIND (not defined) | built-in: events/defaults/FIND.sh | the built-in script
 GITS_PUSH_BEFORE_PUSH (not defined) | (none) | (no script)
 GITS_PUSH_AFTER_PUSH=\"~/after.sh\" | (none) | ${HOME}/after.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: rows of events, old names and NO_COLOR"

# And the number of rows of the table: a line with two "|" which starts with a name of a
# variable. 7 of gits itself + 4 old names + HOME, NO_COLOR (2) + GITS_EVENT_RUNNING, GITS_START, GITS_EXIT (3) + 148 of events.
COMMAND='gits --help 2>&1 | grep -c "^  [A-Z_]*[ =].* | .* | "'
EXPECTED_STDOUT="164"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: all variables are listed"

# Output of "gits" and of "gits --help" compared with diff: no difference (empty output, exit code 0)
# means that calling gits without arguments shows the help.
COMMAND='diff <(gits 2>&1) <(gits --help 2>&1)'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no arguments is --help"

# ---------- help doesn't fail without GITS_SOURCE, but it says that it is a problem ----------

# Everything inside is executed twice: with GITS_SOURCE removed from env ("unset") and with
# GITS_SOURCE defined as an empty text ("empty"). gits has to treat both the same.
for VALUE in unset empty; do
  # prepare the env of this round
  if [[ "${VALUE}" == "unset" ]]; then
    unset GITS_SOURCE
  else
    export GITS_SOURCE=""
  fi

  # The help must not fail without the required variable (exit code 0): it is the place where one
  # reads what is missing. It marks the variable as "MISSING (required)" and explains it below the table.
  COMMAND='gits --help 2>&1 | has "MISSING (required)" "GITS_SOURCE is not defined"'
  EXPECTED_STDOUT="MISSING (required)
GITS_SOURCE is not defined"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "--help without GITS_SOURCE (${VALUE})"

  # The version needs nothing: still printed. "dev" is the version of a binary built by compile.sh.
  COMMAND='gits --version'
  EXPECTED_STDOUT="gits dev"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "--version without GITS_SOURCE (${VALUE})"

  # Every command of gits, one after another: without GITS_SOURCE none of them starts to work.
  for CMD in state find diff isinsync push pull url init add move migrate; do
    # The command ends with exit code 1 and the message which names the variable.
    # isinsync ends with 2: for it 1 means "not in sync", and this is an error.
    # (COMMAND is in double quotes here: ${CMD} has to be put in now, by the loop.)
    COMMAND="gits ${CMD} 2>&1 | has 'env var GITS_SOURCE is not defined or empty'"
    EXPECTED_STDOUT="env var GITS_SOURCE is not defined or empty"
    EXPECTED_STDERR=""
    EXPECTED_CODE="1"
    if [[ "${CMD}" == "isinsync" ]]; then
      EXPECTED_CODE="2"
    fi
    test "${CMD} without GITS_SOURCE (${VALUE})"
  done
done

# Names in ${WORK}: only what tests/_lib.sh prepared (the storage, the git config, the home directory).
# None of the failed commands above left anything: no temporary clone, no config.
COMMAND='listing "${WORK}"'
EXPECTED_STDOUT="GITS_SOURCE gitconfig home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created"

# the storage is defined again for the rest of the test
export GITS_SOURCE="${STORAGE}"

# ---------- wrong arguments ----------

# A command which doesn't exist: exit code 1, and the message repeats what was typed.
COMMAND='gits whatever 2>&1 | has "unknown command >whatever<"'
EXPECTED_STDOUT="unknown command >whatever<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unknown command"

# A flag gits doesn't know (push has only --yes): refused with exit code 1, nothing is guessed.
COMMAND='gits push --force 2>&1 | has "unsupported flag --force"'
EXPECTED_STDOUT="unsupported flag --force"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unsupported flag"

# ---------- commands of a project in a directory which is not one ----------

# The current directory (${WORK}) is not a project: there is no .git/gits.sh in it.
# Every command which works with the project of the current directory is tried.
for CMD in diff push pull url "push --yes" "pull --yes"; do
  # Exit code 1 and the message says which file is missing and how to create it (gits init).
  COMMAND="gits ${CMD} 2>&1 | has \".git/gits.sh< doesn't exist, create it with: gits init\""
  EXPECTED_STDOUT=".git/gits.sh< doesn't exist, create it with: gits init"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "${CMD} without config"
done

# isinsync answers with its exit code only: 0 = in sync, 1 = not in sync. "There is no config" is
# neither of them, it is an error: exit code 2. Its output is thrown away, only the code is checked.
COMMAND='gits isinsync > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "isinsync without config"

# Once more the names in ${WORK}: the commands refused in the last two sections created nothing either.
COMMAND='listing "${WORK}"'
EXPECTED_STDOUT="GITS_SOURCE gitconfig home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created at the end"
