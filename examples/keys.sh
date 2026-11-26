#
# Creates the ssh key of the demo examples/ENCRYPT_PROCESS.md: a key pair without a passphrase,
# ${GITS_DEMO_SSH_KEY} (private) and ${GITS_DEMO_SSH_KEY}.pub (public), see env.sh.
# When the key is already there nothing is changed.
#
#   /bin/bash examples/keys.sh        (from any directory)
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

if [[ -f "${GITS_DEMO_SSH_KEY}" ]]; then
  echo "the key is already there: ${GITS_DEMO_SSH_KEY}"
  exit 0
fi

mkdir -p "$(dirname "${GITS_DEMO_SSH_KEY}")"

ssh-keygen -q -t ed25519 -N "" -C gits-demo -f "${GITS_DEMO_SSH_KEY}" || {
  echo "${0} error: ssh-keygen failed, GITS_DEMO_SSH_KEY=>${GITS_DEMO_SSH_KEY}<"
  exit 1
}

echo "key created: ${GITS_DEMO_SSH_KEY} and ${GITS_DEMO_SSH_KEY}.pub"
