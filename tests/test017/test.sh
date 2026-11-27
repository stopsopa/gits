#
# gits --env [export]: prints the env vars of gits which are defined in the environment AND change
# something, in a form a shell can read back: eval "$(gits --env export)".
#
# What is tested, in this order:
#
#   1. nothing of gits is defined: nothing is printed, exit code 0 (also without GITS_SOURCE)
#   2. what is NOT listed: not defined, empty, only spaces, the value of the default
#      (GITS_SHELL=/bin/bash, GITS_CONFIRM=true)
#   3. what is listed, in the order of the table of gits --help, with spaces at the ends removed
#      (the value gits uses); variables of lifecycle events too
#   4. --env export: the same lines with "export " in front
#   5. the names from before the rename (GITSTORAGE...): listed under the old name when only
#      that one is defined, not listed when the new one is defined too (gits ignores it)
#   6. values with spaces, quotes, $ and ~ are quoted: eval gives back exactly the same values
#   7. a wrong argument: an error, exit code 1
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test017/test.sh
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

# Remove what the previous run of this test left in tests/testNNN/tmp.
if [[ -d "${_DIR}/tmp" ]]; then
  chmod -R u+w "${_DIR}/tmp"
  rm -rf "${_DIR}/tmp"
fi

# Shared setup, see tests/_lib.sh. It defines GITS_SOURCE and unsets every other variable of gits.
source "${_DIR}/../_lib.sh"

unset GITS_SOURCE
unset GITS_PULL_TO_SYNC

# 1. Nothing is defined, not even the required GITS_SOURCE: nothing to print, and no error.
COMMAND='gits --env; gits --env export'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing defined: nothing printed"

# 2. Defined, but gits works exactly like without them: empty and only spaces count as not
# defined, the two others have the value of their default.
COMMAND='GITS_SOURCE="" GITS_ENCRYPTION_SOCKET="  " GITS_SHELL="/bin/bash" GITS_CONFIRM="true" GITS_EXIT="" gits --env'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "empty values and values of the defaults are not listed"

# 3. The order is the one of the table of --help, not the one they were defined in.
# GITS_CONFIRM has spaces around: gits uses "false", so that is printed.
export GITS_PUSH_START="/scripts/push.sh"
export GITS_STATE_FIND="/scripts/find.sh"
export GITS_ALL="/scripts/all.sh"
export GITS_START="/scripts/start.sh"
export GITS_CONFIRM=" false "
export GITS_PULL_TO_SYNC="/clone"
export GITS_SHELL="/bin/sh"
export GITS_SOURCE="git@github.com:owner/storage.git"

COMMAND='gits --env'
EXPECTED_STDOUT="GITS_SOURCE=git@github.com:owner/storage.git
GITS_SHELL=/bin/sh
GITS_PULL_TO_SYNC=/clone
GITS_CONFIRM=false
GITS_START=/scripts/start.sh
GITS_ALL=/scripts/all.sh
GITS_STATE_FIND=/scripts/find.sh
GITS_PUSH_START=/scripts/push.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--env: what is defined and differs from the default"

# 4. The same with export in front of every line.
COMMAND='gits --env export'
EXPECTED_STDOUT="export GITS_SOURCE=git@github.com:owner/storage.git
export GITS_SHELL=/bin/sh
export GITS_PULL_TO_SYNC=/clone
export GITS_CONFIRM=false
export GITS_START=/scripts/start.sh
export GITS_ALL=/scripts/all.sh
export GITS_STATE_FIND=/scripts/find.sh
export GITS_PUSH_START=/scripts/push.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--env export"

unset GITS_PUSH_START GITS_STATE_FIND GITS_ALL GITS_START GITS_CONFIRM GITS_PULL_TO_SYNC GITS_SHELL GITS_SOURCE

# 5. Only the old name is defined: gits reads it, so it is listed, under the name it has.
COMMAND='GITSTORAGESOURCE="/old/storage" gits --env'
EXPECTED_STDOUT="GITSTORAGESOURCE=/old/storage"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "old name alone is listed"

# Both are defined: gits ignores the old one, so only the new one is listed.
COMMAND='GITSTORAGESOURCE="/old/storage" GITS_SOURCE="/new/storage" gits --env'
EXPECTED_STDOUT="GITS_SOURCE=/new/storage"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "old name is not listed when the new one is defined"

# 6. Values a shell would change are in single quotes.
# GITS_EXIT runs at the end of every start of gits, also of --env: the script has to exist.
touch "${HOME}/exit.sh"
export GITS_SOURCE="/a b/it's \"here\""
export GITS_EXIT="~/exit.sh"
export GITS_PUSH_END="\$HOME/a;b"

COMMAND='gits --env'
EXPECTED_STDOUT="GITS_SOURCE='/a b/it'\\''s \"here\"'
GITS_EXIT='~/exit.sh'
GITS_PUSH_END='\$HOME/a;b'"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "values with special characters are quoted"

# Read back by a shell which has none of them: the values are exactly the ones above.
LINES_PLAIN="$("${BIN}" --env)"
LINES_EXPORT="$("${BIN}" --env export)"
unset GITS_SOURCE GITS_EXIT GITS_PUSH_END

COMMAND='eval "${LINES_PLAIN}"; echo ">${GITS_SOURCE}< >${GITS_EXIT}< >${GITS_PUSH_END}<"; env | grep -c "^GITS_PUSH_END="'
EXPECTED_STDOUT=">/a b/it's \"here\"< >~/exit.sh< >\$HOME/a;b<
0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "eval of --env: the same values, as variables of the shell (not exported)"

COMMAND='eval "${LINES_EXPORT}"; /bin/bash -c "echo \">\${GITS_SOURCE}< >\${GITS_EXIT}< >\${GITS_PUSH_END}<\""'
EXPECTED_STDOUT=">/a b/it's \"here\"< >~/exit.sh< >\$HOME/a;b<"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "eval of --env export: the same values, in the environment"

# GITS_EVENT_RUNNING (defined by gits for the scripts of events) is read by gits too: listed.
COMMAND='GITS_EVENT_RUNNING="1" gits --env'
EXPECTED_STDOUT="GITS_EVENT_RUNNING=1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "GITS_EVENT_RUNNING is listed"

# 7. Anything else than "export" after --env.
COMMAND='gits --env exports 2>&1; echo "code ${?}"; gits --env export more 2>&1'
EXPECTED_STDOUT="gits error: --env takes nothing or 'export': gits --env, gits --env export
code 1
gits error: --env takes nothing or 'export': gits --env, gits --env export"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong argument"
