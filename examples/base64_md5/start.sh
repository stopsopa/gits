#
# Starts what gits needs to encode and decode (demo examples/base64_md5/ENCRYPT_PROCESS.md), and
# ends only when it works:
#
#   1. the server examples/base64_md5/server.ts on the socket ${GITS_ENCRYPTION_SOCKET}
#      (TypeScript executed by Node directly, Node.js >= 22.18: nothing is built)
#   2. a test through that socket: a file is encoded, decoded and compared
#
# Exit code 0: gits can use the socket. Anything else: an error was printed.
#
# gits.sh registers it in GITS_START: gits runs it once, as the first thing of a command,
# waits for it, and when it fails gits stops.
# By hand (from any directory), stop it with stop.sh:
#
#   /bin/bash examples/base64_md5/start.sh
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
NODE_OPTIONS="" nohup node "${_DIR}/server.ts" < /dev/null >> "${GITS_DEMO_LOG:-/dev/null}" 2>&1 &
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

# 2. The test. It also fails when nobody listens.
NODE_OPTIONS="" node "${_DIR}/server.ts" test || fail "encoding through GITS_ENCRYPTION_SOCKET=>${GITS_ENCRYPTION_SOCKET}< doesn't work, log: GITS_DEMO_LOG=>${GITS_DEMO_LOG}<"
