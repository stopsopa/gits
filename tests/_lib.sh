#
# Shared setup of all tests of gits. Every check of a test goes through function "test"
# of the library bash/test.sh (this file sources it), this file only prepares the place where
# the commands run and gives few helpers to use inside of COMMAND.
#
# Source it at the top of every tests/testNNN/test.sh, after defining _DIR (directory of the test):
#
#   source "${_DIR}/../_lib.sh"
#
#   COMMAND='gits diff 2>&1 | has "files are in sync"'
#   EXPECTED_STDOUT="files are in sync"
#   EXPECTED_STDERR=""
#   EXPECTED_CODE="0"
#   test "diff in sync"
#
# All four (COMMAND, EXPECTED_STDOUT, EXPECTED_STDERR, EXPECTED_CODE) are required before every "test",
# they are unset after it. stdin of COMMAND is /dev/null.
# COMMAND is executed by eval in a subshell: variables and functions of the test are visible in it
# (so write it in single quotes and let it expand there), but "cd" or "export" made inside of it
# are gone after the test - do such things between the tests.
# "set -o pipefail" is on: exit code of "gits ... | has ..." is the exit code of gits.
#
# What the test gets:
#   _ROOT  - root of the repository
#   BIN    - compiled gits binary (compile.sh)
#   WORK   - temporary directory, removed when the test ends. Nothing is created in tests/
#   HOME   - ${WORK}/home (empty: "~/..." sources and the git config of the developer can't influence the test)
#   pwd    - ${WORK}
#   GITSTORAGESOURCE - ${WORK}/GITSTORAGESOURCE, an empty bare repository: the storage
#                      (bare, because a repository with a working tree refuses a push to its checked out branch)
#   all other GITSTORAGE* / GITS_* env vars unset
#
# git is isolated too: its global config is ${WORK}/gitconfig (identity for commits, default branch "main").
#
# Helpers for COMMAND:
#   gits <args>                 the binary
#   has <fragment> ...          filter: prints (one per line, in the order given) those fragments which are
#                               in stdin. For long outputs where only few things matter, also
#                               for "should not be there": give the fragment and don't expect it
#   listing [directory]         names in the directory (hidden too), sorted, in one line
#   stored <file>               content of the file as it is in the storage right now
#   storage_commits             number of commits in the storage
# Helpers for the setup between the tests:
#   project <directory> <remote>, storage <directory>, socket_server [key], fail <message>
#
# WARNING: bash/test.sh defines function "test", so the builtin "test" is not available in the tests
# (use [[ ... ]]), and COMMAND, EXPECTED_*, RESULT_*, LABEL, STOP are its variables.
#

_ROOT="$(cd "${_DIR}/../.." && pwd)"

source "${_ROOT}/bash/detect_arch.sh"

BIN="${GITS_BIN_PATH}"

if [[ ! -f "${BIN}" ]]; then
  echo "${0} error: binary not found at >${BIN}<. Run compile.sh first."
  exit 1
fi

if [[ ! -f "${_ROOT}/bash/test.sh" ]]; then
  echo "${0} error: test library not found at >${_ROOT}/bash/test.sh<"
  exit 1
fi

unset GITSTORAGESOURCE
unset GITSTORAGETEMPLATE
unset GITSTORAGETESHELL
unset GITSTORAGETENCRYPTIONSOCKET
unset GITS_RELEASES
unset GITS_CONFIRM
unset GITS_TEST_ANSWER
unset NO_COLOR

WORK="$(cd "$(mktemp -d)" && pwd -P)"

SOCKET_SERVER_PID=""

source "${_ROOT}/bash/test.sh" "${0}"

set -o pipefail

# the library registers "trap test_result EXIT", here the same and the cleaning before it
# (exit code of the script is taken first and passed, test_result can't see it after the cleaning)
function _lib_exit {
  local CODE="${?}"
  if [[ -n "${SOCKET_SERVER_PID}" ]]; then
    kill "${SOCKET_SERVER_PID}" 2> /dev/null
    wait "${SOCKET_SERVER_PID}" 2> /dev/null
  fi
  cd /
  rm -rf "${WORK}"
  test_result "${CODE}"
}

trap _lib_exit EXIT

# for tools which need their config from the real one (cargo, rustup)
REAL_HOME="${HOME}"

mkdir -p "${WORK}/home"
export HOME="${WORK}/home"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
cat <<EEE > "${GIT_CONFIG_GLOBAL}"
[user]
  name = gits test
  email = gits-test@localhost
[init]
  defaultBranch = main
[commit]
  gpgsign = false
[advice]
  detachedHead = false
EEE

export GITSTORAGESOURCE="${WORK}/GITSTORAGESOURCE"
git init -q --bare "${GITSTORAGESOURCE}"

cd "${WORK}"

# something in the setup of the test (not a check) went wrong: the whole test failed
function fail {
  echo "${0} error: ${1}"
  FINAL_EXIT_CODE="1"
  exit 1
}

function gits {
  "${BIN}" "${@}"
}

function has {
  local TEXT
  local FRAGMENT
  TEXT="$(cat)"
  for FRAGMENT in "${@}"; do
    if [[ "${TEXT}" == *"${FRAGMENT}"* ]]; then
      printf '%s\n' "${FRAGMENT}"
    fi
  done
  return 0
}

function listing {
  ls -A "${1:-.}" | LC_ALL=C sort | paste -sd ' ' -
}

# project <directory> <url of remote origin>
# empty repository with a remote, the way a real project looks for gits
function project {
  mkdir -p "${1}"
  git -C "${1}" init -q .
  git -C "${1}" remote add origin "${2}"
}

# storage <directory>
# fresh clone of the storage, to look at what is really stored
function storage {
  rm -rf "${1}"
  git clone -q "${GITSTORAGESOURCE}" "${1}" 2> /dev/null || fail "can't clone the storage to >${1}<"
}

# stored <file, path from the root of the storage>
# the clone stays in ${WORK}/look
function stored {
  storage "${WORK}/look"
  cat "${WORK}/look/${1}"
}

# number of commits in the storage (0 when it is empty)
function storage_commits {
  git -C "${GITSTORAGESOURCE}" rev-list --count --all 2> /dev/null || echo 0
}

# socket_server [key]
# starts tests/_socket_server.mjs (stand-in for the encoder process of submodules/encrypt)
# and exports GITSTORAGETENCRYPTIONSOCKET
function socket_server {
  local SOCK="${WORK}/enc-${RANDOM}.sock"
  if [[ -n "${SOCKET_SERVER_PID}" ]]; then
    kill "${SOCKET_SERVER_PID}" 2> /dev/null
    wait "${SOCKET_SERVER_PID}" 2> /dev/null
  fi
  HOME="${REAL_HOME}" NODE_OPTIONS="" node "${_ROOT}/tests/_socket_server.mjs" "${SOCK}" "${1:-key-one}" > "${WORK}/socket-server.log" 2>&1 &
  SOCKET_SERVER_PID="${!}"
  local I
  for I in $(seq 1 100); do
    if [[ -S "${SOCK}" ]]; then
      export GITSTORAGETENCRYPTIONSOCKET="${SOCK}"
      return 0
    fi
    sleep 0.05
  done
  cat "${WORK}/socket-server.log"
  fail "tests/_socket_server.mjs didn't start"
}
