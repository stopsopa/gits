#
# Starts what gits needs to encrypt and decrypt (demo examples/encrypt/ENCRYPT_PROCESS.md), and ends
# only when it works:
#
#   1. an ssh-agent of its own, with the key ${GITS_ENCRYPTION_SSH_KEY} loaded (your agent is not touched)
#   2. the server examples/encrypt/server.js on the socket ${GITS_ENCRYPTION_SOCKET}
#   3. a test through that socket: a file is encrypted, decrypted and compared
#
# Exit code 0: gits can use the socket. Anything else: an error was printed.
#
# gits.sh registers it in GITS_START: gits runs it once, as the first thing of a command,
# waits for it, and when it fails gits stops.
# By hand (from any directory), stop it with stop.sh:
#
#   /bin/bash examples/encrypt/start.sh
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

# whatever a previous run left: start from nothing
/bin/bash "${_DIR}/stop.sh"

if [[ ! -f "${GITS_ENCRYPTION_SSH_KEY}" ]]; then
  echo "${0} error: no key GITS_ENCRYPTION_SSH_KEY=>${GITS_ENCRYPTION_SSH_KEY}<, create it: /bin/bash ${_DIR}/keys.sh"
  exit 1
fi

mkdir -p "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp"

# 1. The agent. It prints "SSH_AUTH_SOCK=...; SSH_AGENT_PID=...;": eval defines both, only
#    inside of this script, so ssh-add and the server below talk to this agent.
eval "$(ssh-agent -a "${GITS_DEMO_AGENT}")" > /dev/null

# the agent didn't start (e.g. the path of the socket is too long): SSH_AUTH_SOCK is still the
# one of your terminal, and ssh-add below would load the demo key into YOUR agent
if [[ "${SSH_AUTH_SOCK}" != "${GITS_DEMO_AGENT}" ]]; then
  echo "${0} error: ssh-agent didn't start on GITS_DEMO_AGENT=>${GITS_DEMO_AGENT}<, nothing was loaded anywhere"
  exit 1
fi

echo "${SSH_AGENT_PID}" > "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/agent.pid"

ssh-add -q "${GITS_ENCRYPTION_SSH_KEY}" || {
  echo "${0} error: ssh-add failed for GITS_ENCRYPTION_SSH_KEY=>${GITS_ENCRYPTION_SSH_KEY}<"
  exit 1
}

# rotation (gits crypt rekey): the key the files get has to be in the agent too
if [[ -n "${GITS_ENCRYPTION_REKEY_SSH_KEY}" ]]; then
  ssh-add -q "${GITS_ENCRYPTION_REKEY_SSH_KEY}" || {
    echo "${0} error: ssh-add failed for GITS_ENCRYPTION_REKEY_SSH_KEY=>${GITS_ENCRYPTION_REKEY_SSH_KEY}<"
    /bin/bash "${_DIR}/stop.sh"
    exit 1
  }
fi

# 2. The server, in the background. Its output is the log (or nothing).
#    server.js (built from server.ts) and the binary which encrypts are prepared by encrypt.sh
if [[ ! -f "${_DIR}/server.js" || "${_DIR}/server.ts" -nt "${_DIR}/server.js" ]] || ! command -v "${GITS_DEMO_SSENC}" > /dev/null; then
  /bin/bash "${_DIR}/encrypt.sh" || {
    echo "${0} error: encrypt.sh failed, there is no server to start"
    /bin/bash "${_DIR}/stop.sh"
    exit 1
  }
fi

NODE_OPTIONS="" nohup node "${_DIR}/server.js" < /dev/null >> "${GITS_DEMO_LOG:-/dev/null}" 2>&1 &
PID="${!}"
echo "${PID}" > "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/server.pid"

# it listens: the socket file appears (at most 5 seconds). It died: no reason to wait.
for I in $(seq 1 100); do
  if [[ -S "${GITS_ENCRYPTION_SOCKET}" ]] || ! kill -0 "${PID}" 2> /dev/null; then
    break
  fi
  sleep 0.05
done

# 3. The test. It also fails when nobody listens.
NODE_OPTIONS="" node "${_DIR}/server.js" test || {
  echo "${0} error: encryption through GITS_ENCRYPTION_SOCKET=>${GITS_ENCRYPTION_SOCKET}< doesn't work, log: GITS_DEMO_LOG=>${GITS_DEMO_LOG}<"
  /bin/bash "${_DIR}/stop.sh"
  exit 1
}
