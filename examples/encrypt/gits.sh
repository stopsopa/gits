#
# gits with encryption which starts and stops by itself (demo examples/encrypt/ENCRYPT_PROCESS.md).
# Use it in place of the gits binary, with the same arguments, from any directory:
#
#   /bin/bash examples/encrypt/gits.sh state
#   /bin/bash examples/encrypt/gits.sh diff
#   /bin/bash examples/encrypt/gits.sh push --yes
#
# It only defines env vars and starts the binary. The rest is done by gits:
#
#   GITS_SOURCE              (env.sh) the storage: examples/encrypt/gits_source, created by
#                            reset_setup.sh. GITS_SOURCE of your terminal is ignored
#   GITS_ENCRYPTION_SOCKET   (env.sh) the socket gits sends its encode / decode requests to
#   GITS_ALL=start.sh        script of every lifecycle event; start.sh reacts to START, the first
#                            event of a command: agent + server + a test, gits waits for it
#   GITS_EXIT=stop.sh        the last thing of every start of gits, however it ends
#
# GITS_DEMO_NO_SOCKET=1 /bin/bash examples/encrypt/gits.sh push --yes
#   gits without GITS_ENCRYPTION_SOCKET and without the two scripts: ':e:' is ignored
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

# a clone kept by your own setup belongs to your real storage, not to the storage of the demo
unset GITS_PULL_TO_SYNC

if [[ -n "${GITS_DEMO_NO_SOCKET}" ]]; then
  # gits as if there was no encoder process at all: it ignores ':e:', nothing is started
  unset GITS_ENCRYPTION_SOCKET
else
  export GITS_ALL="${_DIR}/start.sh"
  export GITS_EXIT="${_DIR}/stop.sh"
fi

"${GITS_DEMO_BIN}" "${@}"
