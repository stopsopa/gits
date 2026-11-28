#
# Creates the ssh keys of the demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md, two key pairs
# without a passphrase in ${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/keys (see env.sh):
# key + key.pub, the one in use, and key2 + key2.pub, to change to (gits crypt rekey).
# A key which is already there is not changed.
#
# It only creates files. It does NOT load them into any ssh-agent: that is done by you, into the
# agent of your terminal, and the script prints the command at its end:
#
#   ssh-add examples/encrypt_os_ssh_agent/keys/key examples/encrypt_os_ssh_agent/keys/key2
#
# (to take them out again: ssh-add -d <file>.pub)
#
#   /bin/bash examples/encrypt_os_ssh_agent/keys.sh        (from any directory)
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

KEYS="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/keys"

mkdir -p "${KEYS}" || {
  echo "${0} error: can't create directory >${KEYS}<"
  exit 1
}

for NAME in key key2; do
  KEY="${KEYS}/${NAME}"
  if [[ -f "${KEY}" ]]; then
    echo "the key is already there: ${KEY}"
    continue
  fi
  ssh-keygen -q -t ed25519 -N "" -C "gits-os-agent-demo-${NAME}" -f "${KEY}" || {
    echo "${0} error: ssh-keygen failed, KEY=>${KEY}<"
    exit 1
  }
  echo "key created: ${KEY} and ${KEY}.pub"
done

# which of the two is loaded in the agent of this terminal (only asked, nothing is changed there)
LOADED="$(ssh-add -l 2> /dev/null)"
MISSING=""
for NAME in key key2; do
  FINGERPRINT="$(ssh-keygen -lf "${KEYS}/${NAME}.pub" | cut -d " " -f 2)"
  if [[ "${LOADED}" != *"${FINGERPRINT}"* ]]; then
    MISSING="${MISSING} \"${KEYS}/${NAME}\""
  fi
done

if [[ -n "${MISSING}" ]]; then
  cat <<EEE

not loaded in the ssh-agent of this terminal (SSH_AUTH_SOCK=>${SSH_AUTH_SOCK}<) yet, load them:

  ssh-add${MISSING}

EEE
else
  echo "both keys are loaded in the ssh-agent of this terminal"
fi
