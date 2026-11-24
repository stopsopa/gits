#
# tests/encoder/encoder-start.sh, tests/encoder/encoder-stop.sh and the wrapper gits.sh:
# the encoder process is started when it doesn't run, left alone when it does, and gits.sh
# does that by itself before it starts the binary.
#
# /bin/bash tests/test011/test.sh
#
# Uses the real encoder process of submodules/encrypt with a demo key in a private ssh-agent
# (tests/_lib.sh, the same as tests/test007).
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

demo_key key-one

SOCK="${WORK}/ssenc.sock"
KEY="${WORK}/keys/key-one.pub"
# (STOP is a variable of bash/test.sh)
ENCODER_START="${_ROOT}/tests/encoder/encoder-start.sh"
ENCODER_STOP="${_ROOT}/tests/encoder/encoder-stop.sh"
WRAPPER="${_ROOT}/gits.sh"

# the scripts and the wrapper with everything they need to reach the private agent and node
# (HOME: node may be installed in the real one)
function run {
  SSH_AUTH_SOCK="${AGENT_SOCK}" HOME="${REAL_HOME}" "${@}"
}

# ---------- what is required ----------

COMMAND='run /bin/bash "${ENCODER_START}" 2>&1 | has "env var GITSTORAGETENCRYPTIONSOCKET is not defined"'
EXPECTED_STDOUT="env var GITSTORAGETENCRYPTIONSOCKET is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start without the socket"

COMMAND='GITSTORAGETENCRYPTIONSOCKET="${SOCK}" run /bin/bash "${ENCODER_START}" 2>&1 | has "env var GITS_ENCODER_SSH_KEY is not defined"'
EXPECTED_STDOUT="env var GITS_ENCODER_SSH_KEY is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start without the key"

COMMAND='GITSTORAGETENCRYPTIONSOCKET="${SOCK}" GITS_ENCODER_SSH_KEY="${KEY}" GITS_ENCODER_DIR="${WORK}/nothing" run /bin/bash "${ENCODER_START}" 2>&1 | has "examples/socket/server.ts< not found"'
EXPECTED_STDOUT="examples/socket/server.ts< not found"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start with GITS_ENCODER_DIR which is not the encrypt repository"

# a key which is not in the agent: the process ends, the script says why
ssh-keygen -q -t ed25519 -N "" -C "gits-test-not-loaded" -f "${WORK}/keys/not-loaded" || fail "ssh-keygen failed"

COMMAND='GITSTORAGETENCRYPTIONSOCKET="${SOCK}" GITS_ENCODER_SSH_KEY="${WORK}/keys/not-loaded.pub" run /bin/bash "${ENCODER_START}" > "${WORK}/start.log" 2>&1; CODE="${?}"; cat "${WORK}/start.log" | has "the encoder process could not be started" "is the private key loaded in ssh-agent?"; ls "${WORK}" | has "ssenc.sock.pid"; (exit "${CODE}")'
EXPECTED_STDOUT="the encoder process could not be started
is the private key loaded in ssh-agent?"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start with a key which is not in the agent: error, no pid file left"

COMMAND='GITSTORAGETENCRYPTIONSOCKET="${SOCK}" /bin/bash "${ENCODER_STOP}"'
EXPECTED_STDOUT="encoder process not running (no ${SOCK}.pid), nothing to stop"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop when nothing runs"

# ---------- start, start again, stop, stop again ----------

export GITSTORAGETENCRYPTIONSOCKET="${SOCK}"
export GITS_ENCODER_SSH_KEY="${KEY}"

COMMAND='run /bin/bash "${ENCODER_START}" | has "encoder process started" "socket: ${SOCK}" "log:    ${SOCK}.log"'
EXPECTED_STDOUT="encoder process started
socket: ${SOCK}
log:    ${SOCK}.log"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start"

PID="$(cat "${SOCK}.pid")"

COMMAND='ps -p "${PID}" -o command= | has "examples/socket/server.ts" "--seal"'
EXPECTED_STDOUT="examples/socket/server.ts
--seal"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the process from the pid file is the encoder, started with --seal"

COMMAND='run /bin/bash "${ENCODER_START}"; cat "${SOCK}.pid"'
EXPECTED_STDOUT="encoder process already running, nothing started
  socket: ${SOCK}
${PID}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start again: nothing started, the same process"

# the key is not needed to find out that it runs
COMMAND='GITS_ENCODER_SSH_KEY="" run /bin/bash "${ENCODER_START}" | has "already running"'
EXPECTED_STDOUT="already running"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start again without the key"

echo "secret" > "${WORK}/plain.txt"

COMMAND='echo "encode \"${WORK}/plain.txt\" \"${WORK}/plain.txt.enc\"" | nc -U "${SOCK}" | has "ok encode"; ssenc decrypt --ssh-key "${KEY}" -i "${WORK}/plain.txt.enc"'
EXPECTED_STDOUT="ok encode
secret"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the started process encrypts, the ssenc binary opens the result"

COMMAND='/bin/bash "${ENCODER_STOP}"; kill -0 "${PID}" 2> /dev/null; echo "alive: ${?}"; ls "${WORK}" | has "ssenc.sock.pid" "ssenc.sock.log"'
EXPECTED_STDOUT="encoder process stopped, pid ${PID}
alive: 1
ssenc.sock.log"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop: the process is gone, the pid file too, the log stays"

COMMAND='/bin/bash "${ENCODER_STOP}"'
EXPECTED_STDOUT="encoder process not running (no ${SOCK}.pid), nothing to stop"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop again"

# a pid file which points to something else (a reboot): that process is not killed
sleep 30 &
OTHER="${!}"
echo "${OTHER}" > "${SOCK}.pid"

COMMAND='/bin/bash "${ENCODER_STOP}"; kill -0 "${OTHER}" 2> /dev/null; echo "alive: ${?}"'
EXPECTED_STDOUT="encoder process not running (pid ${OTHER} from ${SOCK}.pid is gone), nothing to stop
alive: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop with a pid of another program: it is left alone"

kill "${OTHER}" 2> /dev/null

# ---------- the wrapper ----------

unset GITSTORAGETENCRYPTIONSOCKET
unset GITS_ENCODER_SSH_KEY

COMMAND='run /bin/bash "${WRAPPER}" --version 2>&1 | has "env var GITS_BIN is not defined"'
EXPECTED_STDOUT="env var GITS_BIN is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper without GITS_BIN"

COMMAND='GITS_BIN="${WORK}/nothing" run /bin/bash "${WRAPPER}" --version 2>&1 | has "is not an executable file"'
EXPECTED_STDOUT="is not an executable file"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper with GITS_BIN which is not a program"

export GITS_BIN="${BIN}"

COMMAND='run /bin/bash "${WRAPPER}" --version; ls "${WORK}" | has "ssenc.sock.pid"'
EXPECTED_STDOUT="gits dev"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper without GITS_ENCODER_SSH_KEY: the binary, nothing is started"

COMMAND='run /bin/bash "${WRAPPER}" whatever > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper passes the exit code of the binary"

# a project with an encrypted element
D="git@github.com:tmp__repo.git"
project repo "git@github.com:tmp/repo.git"
cd repo
printf 'A=1\nB=2\n' > .env
cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"
GITSTORAGELIST=(
    "../.env:e:\$GITSTORAGETARGETDIR/.env"
)
EEE

export GITSTORAGETENCRYPTIONSOCKET="${SOCK}"

COMMAND='run /bin/bash "${WRAPPER}" push --yes 2>&1 | has "can'"'"'t connect to the encoder process"'
EXPECTED_STDOUT="can't connect to the encoder process"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper without GITS_ENCODER_SSH_KEY and nobody listens: error of the binary"

export GITS_ENCODER_SSH_KEY="${KEY}"

COMMAND='run /bin/bash "${WRAPPER}" isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper with GITS_ENCODER_SSH_KEY: the encoder process is started without a word, isinsync works (not in sync)"

PID="$(cat "${SOCK}.pid")"

COMMAND='run /bin/bash "${WRAPPER}" push --yes 2>&1 | has "(encrypted)" "files pushed" "encoder process"; cat "${SOCK}.pid"'
EXPECTED_STDOUT="(encrypted)
files pushed
${PID}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper: push with the process which already runs, nothing about it in the output"

COMMAND='stored "${D}/.env" | has "#ssenc1" "A=1"; ssenc decrypt --ssh-key "${KEY}" -i "${WORK}/look/${D}/.env"; run /bin/bash "${WRAPPER}" isinsync; echo "isinsync: ${?}"'
EXPECTED_STDOUT="#ssenc1
A=1
B=2
isinsync: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored encrypted, the ssenc binary opens it, in sync"

# default socket: ~/.gits/ssenc.sock (HOME of the test)
/bin/bash "${ENCODER_STOP}" > /dev/null
unset GITSTORAGETENCRYPTIONSOCKET

# HOME has to be the one of the test here, and node found through a version manager (asdf, nvm)
# needs the real one: the directory of the real node binary goes to the front of PATH instead
NODE_DIR="$(dirname "$(HOME="${REAL_HOME}" NODE_OPTIONS="" node -e 'console.log(process.execPath)')")"

function run_home {
  SSH_AUTH_SOCK="${AGENT_SOCK}" PATH="${NODE_DIR}:${PATH}" "${@}"
}

COMMAND='run_home /bin/bash "${WRAPPER}" isinsync; echo "isinsync: ${?}"; ls "${HOME}/.gits" | has "ssenc.sock.pid"'
EXPECTED_STDOUT="isinsync: 0
ssenc.sock.pid"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper: default socket is ~/.gits/ssenc.sock"

GITSTORAGETENCRYPTIONSOCKET="${HOME}/.gits/ssenc.sock" /bin/bash "${ENCODER_STOP}" > /dev/null

# the key is not in the agent: gits is not started at all
export GITS_ENCODER_SSH_KEY="${WORK}/keys/not-loaded.pub"
export GITSTORAGETENCRYPTIONSOCKET="${SOCK}"

COMMAND='run /bin/bash "${WRAPPER}" --version 2>&1 | has "the encoder process is not running, gits was not started" "gits dev"'
EXPECTED_STDOUT="the encoder process is not running, gits was not started"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper: the encoder process can't be started, the binary is not called"
