#
# gits with encryption which starts and stops by itself (demo examples/ENCRYPT_PROCESS.md).
# Use it in place of the gits binary, with the same arguments, from any directory:
#
#   /bin/bash examples/gits.sh state
#   /bin/bash examples/gits.sh diff
#   /bin/bash examples/gits.sh push --yes
#
# It only defines env vars and starts the binary. The rest is done by gits:
#
#   GITS_ENCRYPTION_SOCKET   (env.sh) the socket gits sends its encode / decode requests to
#   GITS_ALL=start.sh        script of every lifecycle event; start.sh reacts to START, the first
#                            event of a command: agent + server + a test, gits waits for it
#   GITS_EXIT=stop.sh        the last thing of every start of gits, however it ends
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

if [[ ! -f "${GITS_DEMO_BIN}" ]]; then
  echo "${0} error: gits binary not found GITS_DEMO_BIN=>${GITS_DEMO_BIN}<, compile it: /bin/bash compile.sh"
  exit 1
fi

export GITS_ALL="${_DIR}/start.sh"
export GITS_EXIT="${_DIR}/stop.sh"

"${GITS_DEMO_BIN}" "${@}"
