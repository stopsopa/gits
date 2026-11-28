#
# Stops what start.sh started (demo examples/base64_md5/ENCRYPT_PROCESS.md): the server
# examples/base64_md5/server.ts, and removes its socket and pid file.
# Nothing runs: nothing happens, exit code 0. Prints nothing.
#
# gits.sh registers it in GITS_EXIT: gits runs it as the last thing of every start, however
# it ended (also after an error, Ctrl+C or kill). By hand (from any directory):
#
#   /bin/bash examples/base64_md5/stop.sh
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
if [[ -n "${PID}" && "$(ps -p "${PID}" -o command= 2> /dev/null)" == *"base64_md5/server."* ]]; then
  kill "${PID}"
fi

rm -f "${PID_FILE}" "${GITS_ENCRYPTION_SOCKET}"
