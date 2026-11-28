#
# gits with an encoder process which starts and stops by itself (demo examples/base64_md5/ENCRYPT_PROCESS.md).
# Use it in place of the gits binary, with the same arguments, from any directory:
#
#   /bin/bash examples/base64_md5/gits.sh state
#   /bin/bash examples/base64_md5/gits.sh diff
#   /bin/bash examples/base64_md5/gits.sh push --yes
#
# It only defines env vars and starts the binary. The rest is done by gits:
#
#   GITS_SOURCE              (env.sh) the storage: examples/base64_md5/gits_source, created by
#                            reset_setup.sh. GITS_SOURCE of your terminal is ignored
#   GITS_PULL_TO_SYNC        (env.sh) where gits keeps its clone of the storage between the commands
#   GITS_ENCRYPTION_SOCKET   (env.sh) the socket gits sends its encode / decode requests to
#   GITS_ENCRYPTION_DETECT   (env.sh) detect.sh: tells gits whether a stored file is an encoded one
#   GITS_START=start.sh      once, the first thing of a command: starts the server and tests it.
#                            gits waits for it, and a failure stops gits
#   GITS_EXIT=stop.sh        the last thing of every start of gits, however it ends
#
# GITS_ENCRYPTION_SOCKET= /bin/bash examples/base64_md5/gits.sh push --yes
#   the socket defined as an empty text: gits without the socket and without the two scripts,
#   ':e:' is ignored
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

if [[ -z "${GITS_ENCRYPTION_DETECT}" ]]; then
  # "GITS_ENCRYPTION_DETECT= gits.sh ...": the built-in rule of gits
  unset GITS_ENCRYPTION_DETECT
fi

if [[ -z "${GITS_ENCRYPTION_SOCKET}" ]]; then
  # "GITS_ENCRYPTION_SOCKET= gits.sh ...": gits as if there was no encoder process at all,
  # it ignores ':e:', nothing is started. (the old name of the variable would be read in its place)
  unset GITS_ENCRYPTION_SOCKET GITSTORAGETENCRYPTIONSOCKET
else
  export GITS_START="${_DIR}/start.sh"
  export GITS_EXIT="${_DIR}/stop.sh"
fi

"${GITS_DEMO_BIN}" "${@}"
