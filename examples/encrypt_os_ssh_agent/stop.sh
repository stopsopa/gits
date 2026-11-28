#
# Stops what start.sh started (demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md): the server
# examples/encrypt_os_ssh_agent/server.js, and removes its socket and pid file.
# The ssh-agent is not touched: it is the one of your terminal, start.sh didn't start it, and
# the keys stay loaded in it.
# Nothing runs: nothing happens, exit code 0. Prints nothing.
#
# gits.sh registers it in GITS_EXIT: gits runs it as the last thing of every start, however
# it ended (also after an error, Ctrl+C or kill). By hand (from any directory):
#
#   /bin/bash examples/encrypt_os_ssh_agent/stop.sh
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

PID_FILE="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/server.pid"

# The pid could belong to another program by now (after a reboot): only the server is killed.
PID="$(cat "${PID_FILE}" 2> /dev/null)"
if [[ -n "${PID}" && "$(ps -p "${PID}" -o command= 2> /dev/null)" == *"encrypt_os_ssh_agent/server."* ]]; then
  kill "${PID}"
fi

rm -f "${PID_FILE}" "${GITS_ENCRYPTION_SOCKET}"
