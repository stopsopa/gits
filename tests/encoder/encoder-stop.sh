#
# Stops the encoder process which tests/encoder/encoder-start.sh started and removes its pid file.
# Can be called again and again: when the process doesn't run it only reports that and ends
# with exit code 0.
#
# Only that one process is stopped: the pid is read from <socket>.pid, and it is killed only when
# a process with that pid exists and is the encoder (examples/socket/server.ts).
#
# Usage (from any directory):
#
#   export GITS_ENCRYPTION_SOCKET="${HOME}/.gits/ssenc.sock"
#   /bin/bash tests/encoder/encoder-stop.sh
#
# Env vars:
#   GITS_ENCRYPTION_SOCKET   required   the socket given to tests/encoder/encoder-start.sh
#
# The log (<socket>.log) is left where it is.
#

SOCK="${GITS_ENCRYPTION_SOCKET}"

# "~/" at the beginning: inside of quotes the shell leaves it as it is
SOCK="${SOCK/#\~\//${HOME}/}"

if [[ -z "${SOCK}" ]]; then
  echo "${0} error: env var GITS_ENCRYPTION_SOCKET is not defined, it is the path of the socket of the encoder process"
  exit 1
fi

PIDFILE="${SOCK}.pid"

if [[ ! -f "${PIDFILE}" ]]; then
  echo "encoder process not running (no ${PIDFILE}), nothing to stop"
  exit 0
fi

PID="$(cat "${PIDFILE}")"

if [[ -z "${PID}" ]]; then
  echo "${0} error: no pid found in PIDFILE=>${PIDFILE}<"
  exit 1
fi

# The pid could belong to another program by now (after a reboot): kill only the encoder.
PROCESS="$(ps -p "${PID}" -o command= 2> /dev/null)"

if [[ "${PROCESS}" == *"examples/socket/server.ts"* ]]; then
  if ! kill "${PID}"; then
    echo "${0} error: could not stop the encoder process PID=>${PID}<"
    exit 1
  fi
  # it finishes the request it works on and removes its socket file
  for I in $(seq 1 100); do
    if ! kill -0 "${PID}" 2> /dev/null; then
      break
    fi
    sleep 0.05
  done
  echo "encoder process stopped, pid ${PID}"
else
  echo "encoder process not running (pid ${PID} from ${PIDFILE} is gone), nothing to stop"
fi

rm -f "${PIDFILE}"
