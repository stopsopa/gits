#
# Stops what start.sh started (demo examples/encrypt/ENCRYPT_PROCESS.md): the server examples/encrypt/server.js
# and the ssh-agent of the demo, and removes their sockets and pid files.
# Nothing runs: nothing happens, exit code 0. Prints nothing.
#
# gits.sh registers it in GITS_EXIT: gits runs it as the last thing of every start, however
# it ended (also after an error, Ctrl+C or kill). By hand (from any directory):
#
#   /bin/bash examples/encrypt/stop.sh
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

# stop <pid file> <text which has to be in the command line of the process>
# The pid could belong to another program by now (after a reboot): only the right one is killed.
function stop {
  local PID
  PID="$(cat "${1}" 2> /dev/null)"
  if [[ -n "${PID}" && "$(ps -p "${PID}" -o command= 2> /dev/null)" == *"${2}"* ]]; then
    kill "${PID}"
  fi
  rm -f "${1}"
}

stop "${GITS_DEMO_TMP}/server.pid" "encrypt/server."
stop "${GITS_DEMO_TMP}/agent.pid" "ssh-agent"

rm -f "${GITS_ENCRYPTION_SOCKET}" "${GITS_DEMO_AGENT}"
