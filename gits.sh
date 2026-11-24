#
# Wrapper around the gits binary: makes sure the encoder process runs, then starts the binary
# with the arguments it got. Everything else is the binary: its output, its exit code.
#
# Without it the encoder process (see tests/encoder/encoder-start.sh) has to be started by hand before
# gits is used with a config which has encrypted elements ("SOURCE:e:TARGET").
#
# Register it in ~/.bashrc or ~/.zshrc ("~/" at the beginning of the paths means home directory):
#
#   export GITSTORAGESOURCE="git@github.com:you/storage.git"
#   export GITS_BIN="/path/to/gits"                              # the binary (compile.sh or a release)
#   export GITS_ENCODER_SSH_KEY="~/.ssh/id_ed25519.pub"          # the key to encrypt with
#   alias gits='/bin/bash "/path/to/this/repository/gits.sh"'
#
# Usage: exactly like the binary
#
#   gits state
#   gits push --yes
#
# Env vars:
#   GITS_BIN                      required   path to the gits binary. Nothing is searched or guessed
#   GITS_ENCODER_SSH_KEY          optional   when defined: the encoder process is started with this key
#                                            if it doesn't run yet (tests/encoder/encoder-start.sh)
#                                            when not defined: nothing is started, the binary is called as it is
#   GITSTORAGETENCRYPTIONSOCKET   optional   socket of the encoder process, default ~/.gits/ssenc.sock
#                                            (only when GITS_ENCODER_SSH_KEY is defined)
#   GITS_ENCODER_DIR              optional   see tests/encoder/encoder-start.sh
#   ... and everything the binary reads: gits --help
#
# - The encoder process stays running after gits ends (the next call is fast), stop it with
#   /bin/bash tests/encoder/encoder-stop.sh
# - Nothing is printed when the encoder process runs or was started without problems
#   ("gits isinsync" has to stay silent). A problem with starting it is an error: exit code 1.
# - tests/encoder/encoder-start.sh is found relative to this file: use this file from
#   a checkout of the repository.
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

BIN="${GITS_BIN/#\~\//${HOME}/}"

if [[ -z "${BIN}" ]]; then
  echo "${0} error: env var GITS_BIN is not defined, it is the path to the gits binary" >&2
  exit 1
fi

if [[ ! -x "${BIN}" || -d "${BIN}" ]]; then
  echo "${0} error: GITS_BIN=>${GITS_BIN}< is not an executable file" >&2
  exit 1
fi

if [[ -n "${GITS_ENCODER_SSH_KEY}" ]]; then
  if [[ -z "${GITSTORAGETENCRYPTIONSOCKET}" ]]; then
    export GITSTORAGETENCRYPTIONSOCKET="${HOME}/.gits/ssenc.sock"
  fi
  export GITSTORAGETENCRYPTIONSOCKET="${GITSTORAGETENCRYPTIONSOCKET/#\~\//${HOME}/}"

  STARTED="$(/bin/bash "${_DIR}/tests/encoder/encoder-start.sh" 2>&1)"

  if [[ "${?}" != "0" ]]; then
    cat <<EEE >&2
${STARTED}
${0} error: the encoder process is not running, gits was not started
EEE
    exit 1
  fi
fi

exec "${BIN}" "${@}"
