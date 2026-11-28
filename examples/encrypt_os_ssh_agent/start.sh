#
# Starts what gits needs to encrypt and decrypt (demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md),
# and ends only when it works:
#
#   1. the server examples/encrypt_os_ssh_agent/server.js on the socket ${GITS_ENCRYPTION_SOCKET}.
#      It inherits SSH_AUTH_SOCK, and so does the binary ssenc it starts
#   2. a test through that socket: a file is encrypted, decrypted and compared
#
# It starts no ssh-agent, loads no key and doesn't look into the agent at all: the agent is the
# one of your terminal (SSH_AUTH_SOCK) and loading the key ${GITS_ENCRYPTION_SSH_KEY} into it
# is done by you (ssh-add, see ENCRYPT_PROCESS.md). When the key is not there the test (2) fails,
# with what ssenc said: "key SHA256:... is not loaded in ssh-agent (check: ssh-add -l)".
#
# Exit code 0: gits can use the socket. Anything else: an error was printed.
#
# gits.sh registers it in GITS_START: gits runs it once, as the first thing of a command,
# waits for it, and when it fails gits stops.
# By hand (from any directory), stop it with stop.sh:
#
#   /bin/bash examples/encrypt_os_ssh_agent/start.sh
#
# All variables: env.sh
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

source "${_DIR}/env.sh"

function fail {
  echo "${0} error: ${1}"
  /bin/bash "${_DIR}/stop.sh"
  exit 1
}

# whatever a previous run left: start from nothing
/bin/bash "${_DIR}/stop.sh"

mkdir -p "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp"

# 1. The server, in the background. Its output is the log (or nothing).
#    server.js (built from server.ts) and the binary which encrypts are prepared by encrypt.sh
if [[ ! -f "${_DIR}/server.js" || "${_DIR}/server.ts" -nt "${_DIR}/server.js" ]] || ! command -v "${GITS_DEMO_SSENC}" > /dev/null; then
  /bin/bash "${_DIR}/encrypt.sh" || fail "encrypt.sh failed, there is no server to start"
fi

NODE_OPTIONS="" nohup node "${_DIR}/server.js" < /dev/null >> "${GITS_DEMO_LOG:-/dev/null}" 2>&1 &
PID="${!}"
# not a job of this shell any more: when stop.sh kills it (a failed test below), bash doesn't
# print "Terminated: 15"
disown "${PID}"
echo "${PID}" > "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/server.pid"

# it listens: the socket file appears (at most 5 seconds). It died: no reason to wait.
for I in $(seq 1 100); do
  if [[ -S "${GITS_ENCRYPTION_SOCKET}" ]] || ! kill -0 "${PID}" 2> /dev/null; then
    break
  fi
  sleep 0.05
done

# 2. The test. It also fails when nobody listens, and when the key is not loaded in the agent.
NODE_OPTIONS="" node "${_DIR}/server.js" test || fail "encryption through GITS_ENCRYPTION_SOCKET=>${GITS_ENCRYPTION_SOCKET}< doesn't work, log: GITS_DEMO_LOG=>${GITS_DEMO_LOG}<"
