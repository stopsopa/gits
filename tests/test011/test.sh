#
# What is tested here: the two scripts which keep the encoder process running and the wrapper
# around the gits binary which uses them:
#
#   tests/encoder/encoder-start.sh   starts the encoder process when it doesn't run yet
#   tests/encoder/encoder-stop.sh    stops it
#   gits.sh                          calls encoder-start.sh, then the binary with the same arguments
#
# (the encoder process is what gits asks, through the unix socket GITS_ENCRYPTION_SOCKET,
# to encrypt and decrypt the elements written as "SOURCE:e:TARGET")
#
# In this order:
#
#   1. encoder-start.sh without what it requires: no socket, no key, a directory which is not
#      the encrypt repository, a key which is not loaded in the agent. encoder-stop.sh when nothing runs.
#   2. start, start again (nothing is started, the same process), the process really encrypts,
#      stop (process gone, pid file gone, log stays), stop again.
#   3. stop with a pid file which points to another program: that program is not killed.
#   4. gits.sh: GITS_BIN missing or wrong; without GITS_ENCODER_SSH_KEY it is just the binary;
#      exit code of the binary is passed.
#   5. gits.sh with a project which has an encrypted element: without the key nobody listens (error
#      of the binary); with the key the process is started without a word and isinsync, push work.
#   6. gits.sh without GITS_ENCRYPTION_SOCKET: the socket is ~/.gits/ssenc.sock.
#   7. gits.sh when the encoder process can't be started: the binary is not called at all.
#
# /bin/bash tests/test011/test.sh
#
# Needs:
#   - the real encoder process: submodules/encrypt/examples/socket/server.ts (node >= 22.18),
#     get the submodule with: git submodule update --init submodules/encrypt
#   - a private ssh-agent with a demo key, started by tests/_lib.sh in ${WORK}. The ssh-agent of the
#     developer is never used: SSH_AUTH_SOCK is given to every command explicitly (function "run")
#   - the ssenc binary of submodules/encrypt (rust/bin/ssenc, compiled by tests/test007 or by
#     submodules/encrypt/rust/compile.sh): it opens from outside what the encoder process encrypted
#   - nc: encoder-start.sh asks the socket with it, and one check here sends a request with it
#   - ssh-keygen, ssh-add
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# where this file is (works in bash, zsh and sh): ${_DIR} is the directory of this test
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

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, an empty storage in ${WORK}/GITS_SOURCE, function "test"
# and the helpers used here (has, listing, stored, ssenc, project, demo_key, fail), ${BIN} (the gits
# binary), ${AGENT_SOCK} (socket of the private ssh-agent) and ${REAL_HOME}
source "${_DIR}/../_lib.sh"

# starts the private ssh-agent and makes the demo key ${WORK}/keys/key-one (+ .pub), loaded in
# that agent: the key the encoder process will encrypt with
demo_key key-one

# SOCK           where the encoder process will listen in this test
# KEY            the public key given to the encoder process
# ENCODER_START  \
# ENCODER_STOP    > the three scripts under test
# WRAPPER        /
SOCK="${WORK}/ssenc.sock"
KEY="${WORK}/keys/key-one.pub"
# (the names are not START / STOP: STOP is a variable of bash/test.sh)
ENCODER_START="${_ROOT}/tests/encoder/encoder-start.sh"
ENCODER_STOP="${_ROOT}/tests/encoder/encoder-stop.sh"
WRAPPER="${_ROOT}/gits.sh"

# starts a command the way the scripts and the wrapper need it here:
#   SSH_AUTH_SOCK  the private agent (it is not exported in the tests, so nothing reaches the agent
#                  of the developer by accident)
#   HOME           the real one: node may be installed there by a version manager (asdf, nvm)
function run {
  SSH_AUTH_SOCK="${AGENT_SOCK}" HOME="${REAL_HOME}" "${@}"
}

# ---------- what is required ----------

# nothing is exported yet. Without GITS_ENCRYPTION_SOCKET the script doesn't know where the
# process should listen: it says so and ends with 1.
COMMAND='run /bin/bash "${ENCODER_START}" 2>&1 | has "env var GITS_ENCRYPTION_SOCKET is not defined"'
EXPECTED_STDOUT="env var GITS_ENCRYPTION_SOCKET is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start without the socket"

# the socket is known, nothing answers on it, so a process has to be started: for that the key
# is required. GITS_ENCODER_SSH_KEY is not defined: error, exit code 1.
COMMAND='GITS_ENCRYPTION_SOCKET="${SOCK}" run /bin/bash "${ENCODER_START}" 2>&1 | has "env var GITS_ENCODER_SSH_KEY is not defined"'
EXPECTED_STDOUT="env var GITS_ENCODER_SSH_KEY is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start without the key"

# GITS_ENCODER_DIR is where the checkout of stopsopa/encrypt is. In an empty place there is no
# examples/socket/server.ts to start: error which names the file, exit code 1.
COMMAND='GITS_ENCRYPTION_SOCKET="${SOCK}" GITS_ENCODER_SSH_KEY="${KEY}" GITS_ENCODER_DIR="${WORK}/nothing" run /bin/bash "${ENCODER_START}" 2>&1 | has "examples/socket/server.ts< not found"'
EXPECTED_STDOUT="examples/socket/server.ts< not found"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start with GITS_ENCODER_DIR which is not the encrypt repository"

# a second key pair which is only made, never added to the agent
ssh-keygen -q -t ed25519 -N "" -C "gits-test-not-loaded" -f "${WORK}/keys/not-loaded" || fail "ssh-keygen failed"

# started with that key. The encoder process asks the agent for the key when it starts, doesn't
# get it and ends. The script waits for the socket, sees that the process died, and has to:
#   - end with 1 (the exit code of the script is kept in CODE and given back at the end with
#     "(exit ...)", because the commands after it would hide it)
#   - say that it could not be started and give the hint about ssh-agent (both fragments found
#     in its output, which was written to start.log)
#   - leave no pid file: "ssenc.sock.pid" is looked for in the listing of ${WORK} and is NOT in the
#     expected output
COMMAND='GITS_ENCRYPTION_SOCKET="${SOCK}" GITS_ENCODER_SSH_KEY="${WORK}/keys/not-loaded.pub" run /bin/bash "${ENCODER_START}" > "${WORK}/start.log" 2>&1; CODE="${?}"; cat "${WORK}/start.log" | has "the encoder process could not be started" "is the private key loaded in ssh-agent?"; ls "${WORK}" | has "ssenc.sock.pid"; (exit "${CODE}")'
EXPECTED_STDOUT="the encoder process could not be started
is the private key loaded in ssh-agent?"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "start with a key which is not in the agent: error, no pid file left"

# nothing runs and there is no pid file: stop says that there is nothing to stop. That is not
# an error (exit code 0): the script can be called any time. The whole output is compared.
COMMAND='GITS_ENCRYPTION_SOCKET="${SOCK}" /bin/bash "${ENCODER_STOP}"'
EXPECTED_STDOUT="encoder process not running (no ${SOCK}.pid), nothing to stop"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop when nothing runs"

# ---------- start, start again, stop, stop again ----------

# from here both variables are exported: the scripts get them without naming them in every command
export GITS_ENCRYPTION_SOCKET="${SOCK}"
export GITS_ENCODER_SSH_KEY="${KEY}"

# the real start. The script prints what it started: the three fragments are the first line and
# the lines with the socket and the log (the line with the pid is left out, the number is not
# known in advance). Exit code 0.
COMMAND='run /bin/bash "${ENCODER_START}" | has "encoder process started" "socket: ${SOCK}" "log:    ${SOCK}.log"'
EXPECTED_STDOUT="encoder process started
socket: ${SOCK}
log:    ${SOCK}.log"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start"

# the pid the script wrote next to the socket, for the checks below
PID="$(cat "${SOCK}.pid")"

# what runs under that pid: the command line has the server of the encoder in it and the flag
# --seal, the script always starts it sealed
COMMAND='ps -p "${PID}" -o command= | has "examples/socket/server.ts" "--seal"'
EXPECTED_STDOUT="examples/socket/server.ts
--seal"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the process from the pid file is the encoder, started with --seal"

# start once more while the process runs. The script asks the socket, gets an answer, and
# starts nothing: its two lines of output are compared exactly, and the pid file (third line)
# still has the same pid. Exit code 0. This is why the script can be called before every use of gits.
COMMAND='run /bin/bash "${ENCODER_START}"; cat "${SOCK}.pid"'
EXPECTED_STDOUT="encoder process already running, nothing started
  socket: ${SOCK}
${PID}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start again: nothing started, the same process"

# the same with an empty GITS_ENCODER_SSH_KEY: whether the process runs is found out from the
# socket alone, the key is needed only to start one
COMMAND='GITS_ENCODER_SSH_KEY="" run /bin/bash "${ENCODER_START}" | has "already running"'
EXPECTED_STDOUT="already running"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "start again without the key"

# a plain file to encrypt
echo "secret" > "${WORK}/plain.txt"

# the process which the script started really works. One request written to the socket with nc,
# the way gits sends it: "encode <plain file> <encrypted file>", the reply starts with "ok encode".
# Then the ssenc binary decrypts the result with the same key (through the private agent, see
# function ssenc in tests/_lib.sh) and prints the content of the plain file: "secret".
COMMAND='socket_request "${SOCK}" "encode \"${WORK}/plain.txt\" \"${WORK}/plain.txt.enc\"" | has "ok encode"; ssenc decrypt --ssh-key "${KEY}" -i "${WORK}/plain.txt.enc"'
EXPECTED_STDOUT="ok encode
secret"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the started process encrypts, the ssenc binary opens the result"

# stop. Four things in one command:
#   - the script says which pid it stopped
#   - "kill -0" asks whether the process still exists: exit code 1 ("alive: 1") means it is gone
#   - in the listing of ${WORK} the pid file is looked for and the log is looked for: only the
#     log is in the expected output. The pid file was removed, the log is kept to read it later
COMMAND='/bin/bash "${ENCODER_STOP}"; kill -0 "${PID}" 2> /dev/null; echo "alive: ${?}"; ls "${WORK}" | has "ssenc.sock.pid" "ssenc.sock.log"'
EXPECTED_STDOUT="encoder process stopped, pid ${PID}
alive: 1
ssenc.sock.log"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop: the process is gone, the pid file too, the log stays"

# stop again: the same answer as when nothing ever ran, exit code 0
COMMAND='/bin/bash "${ENCODER_STOP}"'
EXPECTED_STDOUT="encoder process not running (no ${SOCK}.pid), nothing to stop"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop again"

# a process which has nothing to do with the encoder, and its pid written into the pid file:
# what is left after a reboot, when the pid from an old pid file belongs to another program
sleep 30 &
OTHER="${!}"
echo "${OTHER}" > "${SOCK}.pid"

# stop reads the pid, looks at what runs under it, sees that it is not the encoder and kills
# nothing: it reports the process as gone, and "kill -0" says that the other program is still
# alive ("alive: 0"). The stale pid file is removed by the script.
COMMAND='/bin/bash "${ENCODER_STOP}"; kill -0 "${OTHER}" 2> /dev/null; echo "alive: ${?}"'
EXPECTED_STDOUT="encoder process not running (pid ${OTHER} from ${SOCK}.pid is gone), nothing to stop
alive: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stop with a pid of another program: it is left alone"

# the helper process is not needed any more
kill "${OTHER}" 2> /dev/null

# ---------- the wrapper ----------

# the wrapper is tested from a clean state: nothing about the encoder is defined
unset GITS_ENCRYPTION_SOCKET
unset GITS_ENCODER_SSH_KEY

# the wrapper searches for nothing: without GITS_BIN it doesn't know which binary to start.
# Error, exit code 1.
COMMAND='run /bin/bash "${WRAPPER}" --version 2>&1 | has "env var GITS_BIN is not defined"'
EXPECTED_STDOUT="env var GITS_BIN is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper without GITS_BIN"

# GITS_BIN pointing to a file which doesn't exist: refused before anything is started, exit code 1
COMMAND='GITS_BIN="${WORK}/nothing" run /bin/bash "${WRAPPER}" --version 2>&1 | has "is not an executable file"'
EXPECTED_STDOUT="is not an executable file"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper with GITS_BIN which is not a program"

# from here the wrapper starts the binary made by compile.sh
export GITS_BIN="${BIN}"

# GITS_ENCODER_SSH_KEY is not defined: the wrapper is only the binary. --version prints
# "gits dev", and no encoder process was started: "ssenc.sock.pid" is looked for in ${WORK} and is
# NOT in the expected output.
COMMAND='run /bin/bash "${WRAPPER}" --version; ls "${WORK}" | has "ssenc.sock.pid"'
EXPECTED_STDOUT="gits dev"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper without GITS_ENCODER_SSH_KEY: the binary, nothing is started"

# "whatever" is not a command of gits: the binary ends with 1 and the wrapper ends with the
# same code (it replaces itself with the binary, there is nothing in between)
COMMAND='run /bin/bash "${WRAPPER}" whatever > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper passes the exit code of the binary"

# a project with one encrypted element (":e:"), for the checks with real work:
# D is the name of its directory in the storage, the config stores .env encrypted.
# From here the COMMANDs run in ${WORK}/repo.
D="git@github.com:tmp__repo.git"
project repo "git@github.com:tmp/repo.git"
cd repo
printf 'A=1\nB=2\n' > .env
cat <<EEE > .git/gits.sh
GITS_TARGETDIR="${D}"
GITS_LIST=(
    "../.env:e:\$GITS_TARGETDIR/.env"
)
EEE

# gits is told where the encoder process should be, but nothing runs there (it was stopped above)
export GITS_ENCRYPTION_SOCKET="${SOCK}"

# still without GITS_ENCODER_SSH_KEY: the wrapper starts nothing, so the binary finds nobody
# on the socket when it wants to encrypt .env. The error is the one of the binary, exit code 1.
COMMAND='run /bin/bash "${WRAPPER}" push --yes 2>&1 | has "can'"'"'t connect to the encoder process"'
EXPECTED_STDOUT="can't connect to the encoder process"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper without GITS_ENCODER_SSH_KEY and nobody listens: error of the binary"

# with the key the wrapper has everything to start the encoder process by itself
export GITS_ENCODER_SSH_KEY="${KEY}"

# the first call through the wrapper with the key: it starts the encoder process and then
# isinsync. Nothing may be printed: isinsync is silent, and the wrapper says nothing about a
# process it started without problems (stdout and stderr are both compared with ""). Exit code 1
# is the answer of isinsync: not in sync, the storage is still empty.
COMMAND='run /bin/bash "${WRAPPER}" isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper with GITS_ENCODER_SSH_KEY: the encoder process is started without a word, isinsync works (not in sync)"

# the pid of the process the wrapper started
PID="$(cat "${SOCK}.pid")"

# push through the wrapper. The element is marked "(encrypted)" and the files are pushed,
# exit code 0. "encoder process" is looked for in the output and is NOT expected: the wrapper found
# the process running and printed nothing about it. The last line is the pid file: the same pid
# as before, no second process was started.
COMMAND='run /bin/bash "${WRAPPER}" push --yes 2>&1 | has "(encrypted)" "files pushed" "encoder process"; cat "${SOCK}.pid"'
EXPECTED_STDOUT="(encrypted)
files pushed
${PID}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper: push with the process which already runs, nothing about it in the output"

# what was pushed, three ways:
#   - the stored file starts as an ssenc file ("#ssenc1") and has no plain text in it ("A=1" is looked
#     for in the stored file and is not in the expected output from that part)
#   - the ssenc binary opens it with the same key and prints the two plain lines A=1, B=2
#   - isinsync through the wrapper: exit code 0, in sync
COMMAND='stored "${D}/.env" | has "#ssenc1" "A=1"; ssenc decrypt --ssh-key "${KEY}" -i "${WORK}/look/${D}/.env"; run /bin/bash "${WRAPPER}" isinsync; echo "isinsync: ${?}"'
EXPECTED_STDOUT="#ssenc1
A=1
B=2
isinsync: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored encrypted, the ssenc binary opens it, in sync"

# the process is stopped and the variable removed: the next call has to choose the socket by itself
/bin/bash "${ENCODER_STOP}" > /dev/null
unset GITS_ENCRYPTION_SOCKET

# the directory of the real node binary. In the next check HOME has to be the one of the test
# (the default socket is in ~/.gits, and the real home must not be touched), but a node found
# through a version manager (asdf, nvm) works only with the real HOME: so the binary itself is
# asked where it is, and its directory goes to the front of PATH instead.
NODE_DIR="$(dirname "$(HOME="${REAL_HOME}" NODE_OPTIONS="" node -e 'console.log(process.execPath)')")"

# like "run", but with HOME of the test and node found through PATH
function run_home {
  SSH_AUTH_SOCK="${AGENT_SOCK}" PATH="${NODE_DIR}:${PATH}" "${@}"
}

# without GITS_ENCRYPTION_SOCKET the wrapper uses ~/.gits/ssenc.sock. isinsync works (exit
# code 0, in sync: decrypting needs the process, so it runs), and the pid file is in
# ${HOME}/.gits, where HOME is ${WORK}/home.
COMMAND='run_home /bin/bash "${WRAPPER}" isinsync; echo "isinsync: ${?}"; ls "${HOME}/.gits" | has "ssenc.sock.pid"'
EXPECTED_STDOUT="isinsync: 0
ssenc.sock.pid"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrapper: default socket is ~/.gits/ssenc.sock"

# that process is stopped too, the test leaves nothing running
GITS_ENCRYPTION_SOCKET="${HOME}/.gits/ssenc.sock" /bin/bash "${ENCODER_STOP}" > /dev/null

# the key which is not in the agent, on the socket of the test: starting the process will fail
export GITS_ENCODER_SSH_KEY="${WORK}/keys/not-loaded.pub"
export GITS_ENCRYPTION_SOCKET="${SOCK}"

# the wrapper can't start the encoder process: it prints why and ends with 1, and it does not
# start the binary. "gits dev" (what --version would print) is looked for and is NOT in the
# expected output.
COMMAND='run /bin/bash "${WRAPPER}" --version 2>&1 | has "the encoder process is not running, gits was not started" "gits dev"'
EXPECTED_STDOUT="the encoder process is not running, gits was not started"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrapper: the encoder process can't be started, the binary is not called"
