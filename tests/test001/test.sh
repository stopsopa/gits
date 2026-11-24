#
# gits --help, --version, and GITSTORAGESOURCE required by everything else.
#
# /bin/bash tests/test001/test.sh
# /bin/bash test.sh test001
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

source "${_DIR}/../_lib.sh"

STORAGE="${GITSTORAGESOURCE}"

# ---------- help with everything defined ----------

COMMAND='gits --help 2>&1 | has "gits state" "gits --update --check" "variable" "GITSTORAGESOURCE            | ${STORAGE}" "MISSING"'
EXPECTED_STDOUT="gits state
gits --update --check
variable
GITSTORAGESOURCE            | ${STORAGE}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: commands, update, table of env vars, value found in env, nothing is missing"

# columns: variable | found in env | default | used
COMMAND='gits --help 2>&1 | grep "^  GITSTORAGETESHELL  *|" | tr -s " "'
EXPECTED_STDOUT=" GITSTORAGETESHELL | (not defined) | /bin/bash | /bin/bash"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: default value wins when env var is not defined"

COMMAND='GITSTORAGETESHELL=/bin/zsh gits --help 2>&1 | grep "^  GITSTORAGETESHELL  *|" | tr -s " "'
EXPECTED_STDOUT=" GITSTORAGETESHELL | /bin/zsh | /bin/bash | /bin/zsh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--help: the value which wins is the one from env"

COMMAND='diff <(gits 2>&1) <(gits --help 2>&1)'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no arguments is --help"

# ---------- help doesn't fail without GITSTORAGESOURCE, but it says that it is a problem ----------

for VALUE in unset empty; do
  if [[ "${VALUE}" == "unset" ]]; then
    unset GITSTORAGESOURCE
  else
    export GITSTORAGESOURCE=""
  fi

  COMMAND='gits --help 2>&1 | has "MISSING (required)" "GITSTORAGESOURCE is not defined"'
  EXPECTED_STDOUT="MISSING (required)
GITSTORAGESOURCE is not defined"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "--help without GITSTORAGESOURCE (${VALUE})"

  COMMAND='gits --version'
  EXPECTED_STDOUT="gits dev"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "--version without GITSTORAGESOURCE (${VALUE})"

  for CMD in state find diff isinsync push pull url init add move migrate; do
    COMMAND="gits ${CMD} 2>&1 | has 'env var GITSTORAGESOURCE is not defined or empty'"
    EXPECTED_STDOUT="env var GITSTORAGESOURCE is not defined or empty"
    EXPECTED_STDERR=""
    EXPECTED_CODE="1"
    test "${CMD} without GITSTORAGESOURCE (${VALUE})"
  done
done

COMMAND='listing "${WORK}"'
EXPECTED_STDOUT="GITSTORAGESOURCE gitconfig home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created"

export GITSTORAGESOURCE="${STORAGE}"

# ---------- wrong arguments ----------

COMMAND='gits whatever 2>&1 | has "unknown command >whatever<"'
EXPECTED_STDOUT="unknown command >whatever<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unknown command"

COMMAND='gits push --force 2>&1 | has "unsupported flag --force"'
EXPECTED_STDOUT="unsupported flag --force"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unsupported flag"

# ---------- commands of a project in a directory which is not one ----------

for CMD in diff push pull url "push --yes" "pull --yes"; do
  COMMAND="gits ${CMD} 2>&1 | has \".git/gits.sh< doesn't exist, create it with: gits init\""
  EXPECTED_STDOUT=".git/gits.sh< doesn't exist, create it with: gits init"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "${CMD} without config"
done

# isinsync: 1 means "not in sync", an error is 2
COMMAND='gits isinsync > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "isinsync without config"

COMMAND='listing "${WORK}"'
EXPECTED_STDOUT="GITSTORAGESOURCE gitconfig home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was created at the end"
