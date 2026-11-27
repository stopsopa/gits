#
# Starts what gits needs to encrypt and decrypt (demo examples/encrypt/ENCRYPT_PROCESS.md), and ends
# only when it works:
#
#   1. an ssh-agent of its own, with the key ${GITS_DEMO_SSH_KEY} loaded (your agent is not touched)
#   2. the server examples/encrypt/server.ts on the socket ${GITS_ENCRYPTION_SOCKET}
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

if [[ ! -f "${GITS_DEMO_SSH_KEY}" ]]; then
  echo "${0} error: no key GITS_DEMO_SSH_KEY=>${GITS_DEMO_SSH_KEY}<, create it: /bin/bash ${_DIR}/keys.sh"
  exit 1
fi

mkdir -p "${GITS_DEMO_TMP}"

# 1. The agent. It prints "SSH_AUTH_SOCK=...; SSH_AGENT_PID=...;": eval defines both, only
#    inside of this script, so ssh-add and the server below talk to this agent.
eval "$(ssh-agent -a "${GITS_DEMO_AGENT}")" > /dev/null
echo "${SSH_AGENT_PID}" > "${GITS_DEMO_TMP}/agent.pid"

ssh-add -q "${GITS_DEMO_SSH_KEY}" || {
  echo "${0} error: ssh-add failed for GITS_DEMO_SSH_KEY=>${GITS_DEMO_SSH_KEY}<"
  exit 1
}

# rotation (gits crypt rekey): the key the files get has to be in the agent too
if [[ -n "${GITS_DEMO_NEW_SSH_KEY}" ]]; then
  ssh-add -q "${GITS_DEMO_NEW_SSH_KEY}" || {
    echo "${0} error: ssh-add failed for GITS_DEMO_NEW_SSH_KEY=>${GITS_DEMO_NEW_SSH_KEY}<"
    /bin/bash "${_DIR}/stop.sh"
    exit 1
  }
fi

# 2. The server, in the background. Its output is the log (or nothing).
NODE_OPTIONS="" nohup node "${_DIR}/server.ts" < /dev/null >> "${GITS_DEMO_LOG:-/dev/null}" 2>&1 &
PID="${!}"
echo "${PID}" > "${GITS_DEMO_TMP}/server.pid"

# it listens: the socket file appears (at most 5 seconds). It died: no reason to wait.
for I in $(seq 1 100); do
  if [[ -S "${GITS_ENCRYPTION_SOCKET}" ]] || ! kill -0 "${PID}" 2> /dev/null; then
    break
  fi
  sleep 0.05
done

# 3. The test. It also fails when nobody listens.
NODE_OPTIONS="" node "${_DIR}/server.ts" test || {
  echo "${0} error: encryption through GITS_ENCRYPTION_SOCKET=>${GITS_ENCRYPTION_SOCKET}< doesn't work, log: GITS_DEMO_LOG=>${GITS_DEMO_LOG}<"
  /bin/bash "${_DIR}/stop.sh"
  exit 1
}
