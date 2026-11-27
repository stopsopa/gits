#
# Creates the ssh keys of the demo examples/encrypt/ENCRYPT_PROCESS.md, two key pairs without a
# passphrase in ${GITS_DEMO_TMP} (see env.sh): key + key.pub, the one in use, and key2 + key2.pub,
# to change to (gits crypt rekey). A key which is already there is not changed.
#
#   /bin/bash examples/encrypt/keys.sh        (from any directory)
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

mkdir -p "${GITS_DEMO_TMP}"

for NAME in key key2; do
  KEY="${GITS_DEMO_TMP}/${NAME}"
  if [[ -f "${KEY}" ]]; then
    echo "the key is already there: ${KEY}"
    continue
  fi
  ssh-keygen -q -t ed25519 -N "" -C "gits-demo-${NAME}" -f "${KEY}" || {
    echo "${0} error: ssh-keygen failed, KEY=>${KEY}<"
    exit 1
  }
  echo "key created: ${KEY} and ${KEY}.pub"
done
