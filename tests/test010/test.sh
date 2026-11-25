#
# What is tested here: Ctrl+C. gits works in a temporary clone of the storage (a directory with
# a random name in the current directory) and has to remove it also when it is interrupted.
#
# In this order:
#
#   1. three projects are made in ${WORK}/ws. The config of the second one sleeps, so "gits state"
#      is stuck in it for a moment.
#   2. "gits state" is started in the background, in its own process group.
#   3. when it reached the second project: the temporary clone is there (4 directories, not 3).
#   4. SIGINT is sent to the whole process group, what a terminal does on Ctrl+C.
#   5. what gits left: exit code 130, the temporary clone removed, "gits cleaning" and
#      "gits: interrupted" in the output, the third project never processed.
#
# gits state can't run inside of COMMAND here: it has to run while the test does other things
# (look at the directory, send the signal). So it is started by the test itself and the checks
# look at what it left: exit code, output, directory.
#
# /bin/bash tests/test010/test.sh
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# where this file is (works in bash, zsh and sh): ${_DIR} is the directory of this test
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

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, an empty storage in ${WORK}/GITS_SOURCE, function "test"
# and the helpers used here (gits, project, listing, has, fail)
source "${_DIR}/../_lib.sh"

# the directory "gits state" will be started in: it looks for projects below it, and its
# temporary clone will be made in it. Nothing else is in it, so it is easy to count what is there.
mkdir ws
cd ws

# the first project: an ordinary one with one file to store. Quoted 'EEE': the config is written
# as it is. state gets through it quickly, and makes the temporary clone while doing it.
project fast "git@github.com:tmp/fast.git"
echo "x" > fast/file.txt
cat <<'EEE' > fast/.git/gits.sh
GITS_TARGETDIR="git@github.com:tmp__fast.git"
GITS_LIST=(
    "../file.txt::$GITS_TARGETDIR/file.txt"
)
EEE

# the second project (state goes through the projects in alphabetical order: fast, slow, third).
# Its config is a shell script like every config, and this one also does two things when gits
# executes it:
#   touch  leaves a file: the sign for this test that state arrived here
#   sleep  keeps state busy for 3 seconds: time to look at the directory and to interrupt it
# Not quoted EEE: ${WORK} is put in now, \$GITS_TARGETDIR stays for the config.
# The file ../file.txt of this project doesn't exist, it doesn't matter: state never gets that far.
project slow "git@github.com:tmp/slow.git"
cat <<EEE > slow/.git/gits.sh
GITS_TARGETDIR="git@github.com:tmp__slow.git"
GITS_LIST=(
    "../file.txt::\$GITS_TARGETDIR/file.txt"
)
touch "${WORK}/slow-config-started"
sleep 3
EEE

# the third project, with a copy of the config of the first one. It is here to prove that
# state stops: after Ctrl+C it must not be processed.
project third "git@github.com:tmp/third.git"
cp fast/.git/gits.sh third/.git/gits.sh

# everything state prints goes to this file, the last check reads it
LOG="${WORK}/state.log"

# state started in the background. "set -m" (job control) for the moment of starting it:
# the background job gets its own process group, like a command started in a terminal. Without
# it gits would be in the group of this test and the signal below would hit the test too.
# PID is the pid of the background job, which is also the id of its group ("gits" is a
# function of tests/_lib.sh, so the job is a subshell and the binary is its child, in the same group).
set -m
gits state > "${LOG}" 2>&1 &
PID="${!}"
set +m
# where the output of state is, to look at it by hand after the test
echo "${LOG}"
    # printf "\n      Press Enter to continue\n"
    # read

# wait until the config of the second project was started (the file it touches appears):
# at most 200 x 0.05 s = 10 s. When it never appears there is nothing to test: the whole test fails.
for I in $(seq 1 200); do
  [[ -f "${WORK}/slow-config-started" ]] && break
  sleep 0.05
done
[[ -f "${WORK}/slow-config-started" ]] || fail "gits state didn't reach the second project"

# state is sleeping in the config of "slow" right now. The current directory (ws) has the three
# projects and one more directory: the temporary clone with the random name. "ls -A | wc -l"
# counts the names, "tr" removes the spaces macOS puts in front of the number: 4.
COMMAND='ls -A | wc -l | tr -d " "'
EXPECTED_STDOUT="4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "temporary clone exists while state is running"

# SIGINT to the group ("-" in front of the pid): to gits and to the shell which is executing
# the config with the sleep in it
kill -INT -- "-${PID}"

# wait for the background job to end and keep its exit code: the one the gits binary ended with
wait "${PID}"
CODE="${?}"

# a subshell which ends with the exit code gits ended with, so that "test" can compare it:
# 130 = 128 + 2 (SIGINT), what a program interrupted by Ctrl+C conventionally ends with.
# Not 0 and not 1: a script calling gits can tell "interrupted" from "not in sync".
COMMAND='(exit "${CODE}")'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="130"
test "exit code after Ctrl+C"

# the directory again: only the three projects. The temporary clone which was there a moment
# ago (4 names) was removed by gits on its way out.
COMMAND='listing'
EXPECTED_STDOUT="fast slow third"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "temporary clone removed after Ctrl+C"

# the output of state, from the log:
#   "gits cleaning <path>"  the clone was removed by the normal cleaning, with its path in ws
#   "gits: interrupted"     gits says why it stopped
#   "3 : 3"                 the header of the third project. It is looked for too and it is NOT in
#                           the expected output: state stopped at the second project, the rest was
#                           not processed
COMMAND='cat "${LOG}" | has "gits cleaning ${WORK}/ws/" "gits: interrupted" "3 : 3"'
EXPECTED_STDOUT="gits cleaning ${WORK}/ws/
gits: interrupted"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "output after Ctrl+C: cleaning, interrupted, the rest of the projects is not processed"
