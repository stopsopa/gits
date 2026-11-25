#
# Makes sure the encoder process is running: the process gits asks to encrypt and decrypt
# the elements marked "SOURCE:e:TARGET" (gits never encrypts by itself, it sends
# encode / decode requests to the unix socket GITS_ENCRYPTION_SOCKET).
#
# The process is submodules/encrypt/examples/socket/server.ts started with --seal, see
# "socket-002-encoder_process_on_a_socket" in submodules/encrypt/examples/SUMMARY.md.
#
# Can be called again and again (before every use of gits - that is what gits.sh does): when the
# process already answers on the socket nothing is started, the script only reports it and ends
# with exit code 0.
#
# Usage (from any directory):
#
#   export GITS_ENCRYPTION_SOCKET="${HOME}/.gits/ssenc.sock"
#   export GITS_ENCODER_SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
#   /bin/bash tests/encoder/encoder-start.sh
#   gits diff
#   /bin/bash tests/encoder/encoder-stop.sh
#
# Env vars:
#   GITS_ENCRYPTION_SOCKET   required   where the process listens, the same variable gits reads
#   GITS_ENCODER_SSH_KEY          required   the key everything is encrypted with: path of a .pub file or
#                                            a fingerprint (SHA256:...). Its private key has to be loaded
#                                            in the ssh-agent SSH_AUTH_SOCK points to (ssh-add -l)
#   GITS_ENCODER_DIR              optional   checkout of https://github.com/stopsopa/encrypt,
#                                            default: submodules/encrypt of this repository
#
# What it creates, next to the socket:
#   <socket>.pid   pid of the process, tests/encoder/encoder-stop.sh reads it
#   <socket>.log   output of the process, one line per request
#
# The process keeps running after the terminal is closed, stop it with tests/encoder/encoder-stop.sh.
# Needs: node >= 22.18 (runs TypeScript directly), nc, ssh-agent with the key.
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

_ROOT="$(cd "${_DIR}/../.." && pwd)"

SOCK="${GITS_ENCRYPTION_SOCKET}"
KEY="${GITS_ENCODER_SSH_KEY}"
ENCRYPT="${GITS_ENCODER_DIR:-${_ROOT}/submodules/encrypt}"

# "~/" at the beginning: inside of quotes the shell leaves it as it is
SOCK="${SOCK/#\~\//${HOME}/}"
KEY="${KEY/#\~\//${HOME}/}"
ENCRYPT="${ENCRYPT/#\~\//${HOME}/}"

if [[ -z "${SOCK}" ]]; then
  echo "${0} error: env var GITS_ENCRYPTION_SOCKET is not defined, it is the path of the socket the encoder process should listen on"
  exit 1
fi

# The path of a unix socket is limited (104 bytes on macOS, 108 on Linux).
if [[ "${#SOCK}" -gt 100 ]]; then
  echo "${0} error: the socket path is too long (${#SOCK} characters, at most 100), GITS_ENCRYPTION_SOCKET=>${SOCK}<"
  exit 1
fi

PIDFILE="${SOCK}.pid"
LOGFILE="${SOCK}.log"

# Any line sent to the process gets one line back ("ping" is not a request: the reply is an error,
# but it is a reply). Nothing comes back when nobody listens.
#
# nc of Linux (netcat-openbsd) keeps the connection open after its input ended, and the encoder
# process closes a connection only after the client did: without -N ("say: nothing more from me,
# when the input ends") nc would wait forever. nc of macOS does that by itself (its -N means something else), so -N is used only
# when the help of nc describes it as "shutdown ... after EOF".
# -w 2 on top of it: never wait longer than 2 seconds of silence, whatever happens.
NC_EOF=""
if nc -h 2>&1 | grep -q -i "shutdown.*after EOF"; then
  NC_EOF="-N"
fi

if [[ -S "${SOCK}" ]]; then
  REPLY_LINE="$(echo "ping" | nc ${NC_EOF} -w 2 -U "${SOCK}" 2> /dev/null)"
  if [[ -n "${REPLY_LINE}" ]]; then
    cat <<EEE
encoder process already running, nothing started
  socket: ${SOCK}
EEE
    exit 0
  fi
fi

if [[ -z "${KEY}" ]]; then
  echo "${0} error: env var GITS_ENCODER_SSH_KEY is not defined, it is the ssh key to encrypt with: path of a .pub file or a fingerprint (SHA256:...)"
  exit 1
fi

if [[ ! -f "${ENCRYPT}/examples/socket/server.ts" ]]; then
  cat <<EEE
${0} error: >${ENCRYPT}/examples/socket/server.ts< not found.
GITS_ENCODER_DIR=>${GITS_ENCODER_DIR}< has to point to a checkout of https://github.com/stopsopa/encrypt
(in this repository: git submodule update --init submodules/encrypt)
EEE
  exit 1
fi

if ! command -v node > /dev/null 2>&1; then
  echo "${0} error: node not found, the encoder process needs Node.js >= 22.18"
  exit 1
fi

mkdir -p "$(dirname "${SOCK}")"

# Nobody answers: a pid file which is still there was left by a process that died.
rm -f "${PIDFILE}"

# started from "/": the process resolves relative paths of requests against its directory,
# gits always sends absolute ones
(
  cd /
  # The process must not keep anything of the caller open: a caller which reads the output of this
  # script through a pipe ("$(...)", "| cat") would wait for the end of the process, so forever.
  # stdin, stdout and stderr are redirected below, here every other descriptor it would inherit.
  for FD in $(seq 3 255); do
    eval "exec ${FD}>&-" 2> /dev/null
  done
  NODE_OPTIONS="" nohup node "${ENCRYPT}/examples/socket/server.ts" --ssh-key "${KEY}" --seal --socket "${SOCK}" < /dev/null >> "${LOGFILE}" 2>&1 &
  echo "${!}" > "${PIDFILE}"
)

PID="$(cat "${PIDFILE}")"

# it listens after it found the key in the agent; it ends when it can't
for I in $(seq 1 100); do
  if [[ -S "${SOCK}" ]]; then
    cat <<EEE
encoder process started
  socket: ${SOCK}
  pid:    ${PID}
  log:    ${LOGFILE}
EEE
    exit 0
  fi
  if ! kill -0 "${PID}" 2> /dev/null; then
    break
  fi
  sleep 0.05
done

rm -f "${PIDFILE}"

cat <<EEE
${0} error: the encoder process could not be started on GITS_ENCRYPTION_SOCKET=>${SOCK}< with GITS_ENCODER_SSH_KEY=>${KEY}<
(is the private key loaded in ssh-agent? check with: ssh-add -l). Last lines of >${LOGFILE}<:
$(tail -n 5 "${LOGFILE}" 2> /dev/null)
EEE

exit 1
