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
#   WORK   - ${_DIR}/tmp: everything the test produces is there, in the directory of the test itself.
#            It is NOT removed when the test ends (to look at what was left), the test clears it
#            at its beginning. Ignored by git: tests/testNNN/.gitignore
#   HOME   - ${WORK}/home (empty: "~/..." sources and the git config of the developer can't influence the test)
#   pwd    - ${WORK}
#   GITS_SOURCE - ${WORK}/GITS_SOURCE, an empty repository: the storage.
#                      An ordinary one with a working tree (not bare), to see what the test stored
#                      by just looking into that directory when the test ended.
#                      A repository with a working tree refuses a push to its checked out branch,
#                      "receive.denyCurrentBranch updateInstead" makes it accept the push and
#                      update the files of the working tree to what was pushed
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
#   project <directory> <remote>, storage <directory>, fail <message>
# Encryption (only the tests which need it, see the comment above encoder_start):
#   encoder_start [name of the key]     the real encoder process of submodules/encrypt on a unix socket
#   encoder_stop, demo_key <name>
#   socket_request <socket> <line>      one request sent by hand to the encoder process (nc)
#   ssenc <args>                        the ssenc binary of submodules/encrypt (inside of COMMAND)
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

# the names from before the rename are still read by gits when the new ones are not defined:
# the ones of the developer must not leak into a test
unset GITSTORAGESOURCE
unset GITSTORAGETEMPLATE
unset GITSTORAGETESHELL
unset GITSTORAGETENCRYPTIONSOCKET
unset GITS_SOURCE
unset GITS_TEMPLATE
unset GITS_SHELL
unset GITS_ENCRYPTION_SOCKET
unset GITS_RELEASES
unset GITS_CONFIRM
unset GITS_TEST_ANSWER
unset NO_COLOR

# lifecycle scripts of the developer (GITS_ALL, GITS_<COMMAND>_<EVENT>) must not run in a test.
# The names of the commands are enough: every such variable starts with GITS_<COMMAND>_
unset GITS_ALL
for _LIB_NAME in $(env | grep -E '^GITS_(STATE|FIND|INIT|ADD|DIFF|ISINSYNC|PUSH|PULL|URL|MOVE|MIGRATE|UPDATE)_' | cut -d = -f 1); do
  unset "${_LIB_NAME}"
done
unset GITS_EVENT_RUNNING

mkdir -p "${_DIR}/tmp"

WORK="$(cd "${_DIR}/tmp" && pwd -P)"

# ${WORK} is inside of the repository of gits: git started in a directory of the test which is not
# a repository must not walk up and find that one
export GIT_CEILING_DIRECTORIES="${_DIR}"

AGENT_PID=""

source "${_ROOT}/bash/test.sh" "${0}"

set -o pipefail

# the library registers "trap test_result EXIT", here the same and stopping of the socket server before it
# (exit code of the script is taken first and passed, test_result can't see it after that).
# ${WORK} stays as it is.
function _lib_exit {
  local CODE="${?}"
  encoder_stop
  agent_stop
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

export GITS_SOURCE="${WORK}/GITS_SOURCE"
git init -q "${GITS_SOURCE}"
git -C "${GITS_SOURCE}" config receive.denyCurrentBranch updateInstead

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
  git clone -q "${GITS_SOURCE}" "${1}" 2> /dev/null || fail "can't clone the storage to >${1}<"
}

# stored <file, path from the root of the storage>
# the clone stays in ${WORK}/look
function stored {
  storage "${WORK}/look"
  cat "${WORK}/look/${1}"
}

# number of commits in the storage (0 when it is empty)
function storage_commits {
  git -C "${GITS_SOURCE}" rev-list --count --all 2> /dev/null || echo 0
}

# ---------- encryption: the real thing from submodules/encrypt ----------
#
# What submodules/encrypt/examples/SUMMARY.md describes in "socket-002-encoder_process_on_a_socket",
# here everything in ${WORK} of the test:
#
#   ${WORK}/keys/<name>, <name>.pub   demo ssh key without a passphrase (ssh-keygen)
#   ${WORK}/agent.sock                private ssh-agent which holds the demo keys. The agent of the
#                                     developer is never asked and never changed: SSH_AUTH_SOCK is
#                                     not exported, every command here gets it explicitly
#   ${WORK}/ssenc.sock                the encoder process, started by tests/encoder/encoder-start.sh:
#                                     node submodules/encrypt/examples/socket/server.ts --ssh-key <name>.pub --seal
#   ${WORK}/ssenc.sock.log            its output, one line per request
#   ${WORK}/ssenc.sock.pid            its pid
#
# and GITS_ENCRYPTION_SOCKET=${WORK}/ssenc.sock is exported: gits talks to that socket.
#
# The ssenc binary (submodules/encrypt/rust/bin/ssenc) is not used by gits and not by the encoder
# process. The tests use it to look at the stored files from outside: a file gits stored has to be
# an ordinary ssenc file which the binary opens with the same key.

ENCRYPT="${_ROOT}/submodules/encrypt"
AGENT_SOCK="${WORK}/agent.sock"

# the binary is compiled when it is not there yet (the first run, CI)
function ssenc_build {
  if [[ ! -f "${ENCRYPT}/rust/compile.sh" ]]; then
    fail "submodule not found at >${ENCRYPT}<, get it with: git submodule update --init submodules/encrypt"
  fi
  if [[ ! -x "${ENCRYPT}/rust/target/release/ssenc" ]]; then
    echo "compiling ${ENCRYPT}/rust/target/release/ssenc"
    HOME="${REAL_HOME}" /bin/bash "${ENCRYPT}/rust/compile.sh" > "${WORK}/ssenc-compile.log" 2>&1
    if [[ "${?}" != "0" ]]; then
      cat "${WORK}/ssenc-compile.log"
      fail "can't compile ssenc with >${ENCRYPT}/rust/compile.sh<"
    fi
  fi
}

# socket_request <socket> <request line>
# One request sent by hand to the encoder process, its reply on stdout.
# -N: nc of Linux (netcat-openbsd) would otherwise wait forever after the reply (it keeps the
# connection open after its input ended, the encoder process closes it only after the client did).
# nc of macOS needs none (its -N means something else): -N is used only when the help of nc
# describes it as "shutdown ... after EOF". -w 5: never wait longer than 5 seconds of silence.
function socket_request {
  local NC_EOF=""
  if nc -h 2>&1 | grep -q -i "shutdown.*after EOF"; then
    NC_EOF="-N"
  fi
  echo "${2}" | nc ${NC_EOF} -w 5 -U "${1}"
}

function ssenc {
  SSH_AUTH_SOCK="${AGENT_SOCK}" "${ENCRYPT}/rust/bin/ssenc" "${@}"
}

# the private agent, started once per test
function agent_start {
  if [[ -n "${AGENT_PID}" ]]; then
    return 0
  fi
  # limit of the operating system for a path of a unix socket: 104 bytes on macOS, 108 on Linux
  if [[ "${#AGENT_SOCK}" -gt 100 ]]; then
    fail "path of the socket >${AGENT_SOCK}< is too long (${#AGENT_SOCK}, limit is about 100): the repository is too deep in the filesystem"
  fi
  rm -f "${AGENT_SOCK}"
  local OUT
  OUT="$(ssh-agent -a "${AGENT_SOCK}")" || fail "ssh-agent could not be started on >${AGENT_SOCK}<"
  AGENT_PID="$(echo "${OUT}" | grep -o 'SSH_AGENT_PID=[0-9]*' | cut -d = -f 2)"
  # exit code 2: nobody answers on that socket. Without this check a key could end up in another agent
  SSH_AUTH_SOCK="${AGENT_SOCK}" ssh-add -l > /dev/null 2>&1
  if [[ "${?}" == "2" || -z "${AGENT_PID}" ]]; then
    fail "private ssh-agent doesn't answer on >${AGENT_SOCK}<"
  fi
}

function agent_stop {
  if [[ -n "${AGENT_PID}" ]]; then
    # only an ssh-agent is killed, whatever happened to that pid meanwhile
    if [[ "$(ps -p "${AGENT_PID}" -o comm= 2> /dev/null)" == *ssh-agent* ]]; then
      kill "${AGENT_PID}" 2> /dev/null
    fi
    AGENT_PID=""
    rm -f "${AGENT_SOCK}"
  fi
}

# the encoder process is started and stopped with the scripts made for everyday use:
# tests/encoder/encoder-start.sh and tests/encoder/encoder-stop.sh
ENCODER_SOCK="${WORK}/ssenc.sock"

function encoder_stop {
  GITS_ENCRYPTION_SOCKET="${ENCODER_SOCK}" /bin/bash "${_ROOT}/tests/encoder/encoder-stop.sh" >> "${WORK}/encoder-scripts.log" 2>&1
}

# demo_key <name>
# ${WORK}/keys/<name> and <name>.pub, made when not there yet and loaded into the private agent
function demo_key {
  local KEY="${WORK}/keys/${1}"
  agent_start
  if [[ ! -f "${KEY}" ]]; then
    mkdir -p "${WORK}/keys"
    ssh-keygen -q -t ed25519 -N "" -C "gits-test-${1}" -f "${KEY}" || fail "ssh-keygen failed for >${KEY}<"
    SSH_AUTH_SOCK="${AGENT_SOCK}" ssh-add -q "${KEY}" || fail "ssh-add failed for >${KEY}<"
  fi
}

# encoder_start [name of the key]
# (re)starts the encoder process with the given demo key and exports GITS_ENCRYPTION_SOCKET
function encoder_start {
  local NAME="${1:-key-one}"

  demo_key "${NAME}"
  encoder_stop

  # HOME: node may be installed in the real one (asdf, nvm)
  SSH_AUTH_SOCK="${AGENT_SOCK}" HOME="${REAL_HOME}" \
    GITS_ENCRYPTION_SOCKET="${ENCODER_SOCK}" GITS_ENCODER_SSH_KEY="${WORK}/keys/${NAME}.pub" \
    /bin/bash "${_ROOT}/tests/encoder/encoder-start.sh" >> "${WORK}/encoder-scripts.log" 2>&1

  if [[ "${?}" != "0" ]]; then
    cat "${WORK}/encoder-scripts.log"
    fail "tests/encoder/encoder-start.sh failed"
  fi

  export GITS_ENCRYPTION_SOCKET="${ENCODER_SOCK}"
}
