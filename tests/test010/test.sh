#
# Ctrl+C: the temporary clone is removed also then.
#
# /bin/bash tests/test010/test.sh
# /bin/bash test.sh test010
#
# gits state is started in the background (so not inside of COMMAND), interrupted in the moment
# when its temporary clone exists, and the checks look at what it left: exit code, output, directory.
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
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

# what the previous run left (kept after the test to look at it, ignored by git: .gitignore next to this file)
if [[ -d "${_DIR}/tmp" ]]; then
  chmod -R u+w "${_DIR}/tmp"
  rm -rf "${_DIR}/tmp"
fi

source "${_DIR}/../_lib.sh"

mkdir ws
cd ws

project fast "git@github.com:tmp/fast.git"
echo "x" > fast/file.txt
cat <<'EEE' > fast/.git/gits.sh
GITSTORAGETARGETDIR="git@github.com:tmp__fast.git"
GITSTORAGELIST=(
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
)
EEE

# the second project takes long to read: time to press Ctrl+C while the clone exists
project slow "git@github.com:tmp/slow.git"
cat <<EEE > slow/.git/gits.sh
GITSTORAGETARGETDIR="git@github.com:tmp__slow.git"
GITSTORAGELIST=(
    "../file.txt::\$GITSTORAGETARGETDIR/file.txt"
)
touch "${WORK}/slow-config-started"
sleep 3
EEE

project third "git@github.com:tmp/third.git"
cp fast/.git/gits.sh third/.git/gits.sh

LOG="${WORK}/state.log"

# job control: the background job gets its own process group, like a command started in a terminal
set -m
gits state > "${LOG}" 2>&1 &
PID="${!}"
set +m
echo "${LOG}"
    # printf "\n      Press Enter to continue\n"
    # read

for I in $(seq 1 200); do
  [[ -f "${WORK}/slow-config-started" ]] && break
  sleep 0.05
done
[[ -f "${WORK}/slow-config-started" ]] || fail "gits state didn't reach the second project"

# fast, slow, third + one directory with a random name
COMMAND='ls -A | wc -l | tr -d " "'
EXPECTED_STDOUT="4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "temporary clone exists while state is running"

# what the terminal does on Ctrl+C: SIGINT to the whole group (gits and the shell reading the config)
kill -INT -- "-${PID}"

wait "${PID}"
CODE="${?}"

COMMAND='(exit "${CODE}")'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="130"
test "exit code after Ctrl+C"

COMMAND='listing'
EXPECTED_STDOUT="fast slow third"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "temporary clone removed after Ctrl+C"

# "3 : 3": the rest of the projects is not processed
COMMAND='cat "${LOG}" | has "gits cleaning ${WORK}/ws/" "gits: interrupted" "3 : 3"'
EXPECTED_STDOUT="gits cleaning ${WORK}/ws/
gits: interrupted"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "output after Ctrl+C: cleaning, interrupted, the rest of the projects is not processed"
