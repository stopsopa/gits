#
# Lifecycle events, part 2: what the scripts can do and where they come from.
# (part 1, tests/test012, shows which events every command fires and what a script sees)
#
# Every script here appends a line to tests/test013/tmp/log.txt or dumps what it sees into
# tests/test013/tmp/, to look at after the test.
#
# What is tested, in this order:
#
#   1. a START / BEFORE_* script which ends with a non-zero exit code stops the command:
#      nothing is stored, the temporary directory is removed, ERROR and END still fire
#   2. an AFTER_* script which fails is only a warning, the command succeeds
#   3. a variable pointing to a file which doesn't exist: the same two rules
#   4. the path of a script can start with ~/, and a relative path is relative to the directory
#      where gits was called
#   5. the scripts are executed by the shell from GITS_SHELL
#   6. isinsync stays silent on stdout: what a script prints goes to stderr
#   7. scripts defined in .git/gits.sh of a project: they run (GITS_EVENT_TRIGGER_FROM=config),
#      after the script of the environment for the same event, and only for that project
#   8. the replaceable event FIND: the default finds the projects; a script of the user
#      (GITS_STATE_FIND, GITS_FIND_FIND) replaces it; a failing one is an error
#   9. gits called from inside of a script runs no scripts itself (no recursion)
#  10. the names from before the rename (GITSTORAGESOURCE, GITSTORAGETARGETDIR, GITSTORAGELIST,
#      GITSTORAGETESHELL) still work, --help says where a value came from, "gits migrate"
#      renames the variables in a config
#  11. "gits events": every event is listed, the defined ones with their value; the example
#      scripts in events/examples/ are exactly what "gits events --examples" writes
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test013/test.sh
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

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, an empty storage in ${WORK}/GITS_SOURCE, function "test"
# and the helpers used here (gits, project, listing, has, fail)
source "${_DIR}/../_lib.sh"

D="git@github.com:tmp__repo.git"
LOG="${WORK}/log.txt"
export LOG

mkdir "${WORK}/scripts"

# says which event it is, into the log
cat <<'EEE' > "${WORK}/scripts/log.sh"
echo "${GITS_EVENT} (${GITS_EVENT_TRIGGER_FROM})" >> "${LOG}"
EEE

# the same, and then fails
cat <<'EEE' > "${WORK}/scripts/fail.sh"
echo "${GITS_EVENT} (${GITS_EVENT_TRIGGER_FROM}) FAILS" >> "${LOG}"
echo "this script says no"
exit 7
EEE

# a project with one file, in sync with the storage
project repo "git@github.com:tmp/repo.git"
cd repo
echo 'one' > file.txt
cat <<EEE > .git/gits.sh
GITS_TARGETDIR="${D}"
GITS_LIST=(
    "gits.sh::\$GITS_TARGETDIR/gits.sh"
    "../file.txt::\$GITS_TARGETDIR/file.txt"
)
EEE
gits push --yes > /dev/null 2>&1 || fail "the first push failed"

# ---------- a START script which fails stops the command ----------

echo 'two' > file.txt
rm -f "${LOG}"

# START fails with exit code 7: gits reports it, ends with 1 and did nothing: no clone was made
# (no "Cloning" in the output), the storage still has one commit. ERROR and END fired anyway.
COMMAND='GITS_PUSH_START="${WORK}/scripts/fail.sh" GITS_PUSH_ERROR="${WORK}/scripts/log.sh" GITS_PUSH_END="${WORK}/scripts/log.sh" gits push --yes 2>&1 | has "this script says no" "event GITS_PUSH_START (START, defined in env): script >${WORK}/scripts/fail.sh< ended with exit code 7 - the command is stopped" "Cloning"; storage_commits; cat "${LOG}"'
EXPECTED_STDOUT="this script says no
event GITS_PUSH_START (START, defined in env): script >${WORK}/scripts/fail.sh< ended with exit code 7 - the command is stopped
1
GITS_PUSH_START (env) FAILS
GITS_PUSH_ERROR (env)
GITS_PUSH_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "START script fails: the command is stopped before it did anything, ERROR and END still fire"

COMMAND='GITS_PUSH_START="${WORK}/scripts/fail.sh" gits push --yes > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "START script fails: exit code 1"

# ---------- a BEFORE_PUSH script which fails: the last moment to refuse ----------

rm -f "${LOG}"

# Everything was prepared (clone, copy, commit in the clone), and then BEFORE_PUSH says no:
# the storage is not touched (still one commit), the temporary directory is removed
# (the project has only its own files), CLEANUP events still fire.
COMMAND='GITS_PUSH_BEFORE_PUSH="${WORK}/scripts/fail.sh" GITS_PUSH_AFTER_PUSH="${WORK}/scripts/log.sh" GITS_PUSH_AFTER_CLEANUP="${WORK}/scripts/log.sh" GITS_PUSH_ERROR="${WORK}/scripts/log.sh" GITS_PUSH_END="${WORK}/scripts/log.sh" gits push --yes > /dev/null 2>&1; echo "exit code ${?}"; storage_commits; listing; cat "${LOG}"'
EXPECTED_STDOUT="exit code 1
1
.git file.txt
GITS_PUSH_BEFORE_PUSH (env) FAILS
GITS_PUSH_AFTER_CLEANUP (env)
GITS_PUSH_ERROR (env)
GITS_PUSH_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "BEFORE_PUSH script fails: nothing reaches the storage, the temporary directory is removed"

# ---------- an AFTER_* script which fails is only a warning ----------

rm -f "${LOG}"

# AFTER_PUSH can't undo the push: its failure is reported as a warning, the exit code stays 0
# and the storage has the second commit.
COMMAND='GITS_PUSH_AFTER_PUSH="${WORK}/scripts/fail.sh" gits push --yes 2>&1 | has "gits warning: event GITS_PUSH_AFTER_PUSH (AFTER_PUSH, defined in env): script >${WORK}/scripts/fail.sh< ended with exit code 7" "files pushed" "the command is stopped"; storage_commits'
EXPECTED_STDOUT="gits warning: event GITS_PUSH_AFTER_PUSH (AFTER_PUSH, defined in env): script >${WORK}/scripts/fail.sh< ended with exit code 7
files pushed
2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "AFTER_PUSH script fails: a warning, the push is done, exit code 0"

# ---------- a variable which points to nothing ----------

# the same two rules: BEFORE_* stops the command, AFTER_* warns
COMMAND='GITS_DIFF_BEFORE_CLONE="${WORK}/scripts/nothing.sh" gits diff 2>&1 | has "script >${WORK}/scripts/nothing.sh< doesn'"'"'t exist - the command is stopped" "files are in sync"'
EXPECTED_STDOUT="script >${WORK}/scripts/nothing.sh< doesn't exist - the command is stopped"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "BEFORE_* points to a file which doesn't exist: the command is stopped"

COMMAND='GITS_DIFF_AFTER_CLONE="${WORK}/scripts/nothing.sh" gits diff 2>&1 | has "gits warning: event GITS_DIFF_AFTER_CLONE (AFTER_CLONE, defined in env): script >${WORK}/scripts/nothing.sh< doesn'"'"'t exist" "files are in sync"'
EXPECTED_STDOUT="gits warning: event GITS_DIFF_AFTER_CLONE (AFTER_CLONE, defined in env): script >${WORK}/scripts/nothing.sh< doesn't exist
files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "AFTER_* points to a file which doesn't exist: a warning"

# ---------- the path: ~/ and relative ----------

mkdir -p "${HOME}/.gits/events"
cp "${WORK}/scripts/log.sh" "${HOME}/.gits/events/home.sh"
cp "${WORK}/scripts/log.sh" relative.sh
rm -f "${LOG}"

# "~/" is the home (the one of the test here); "relative.sh" is in the directory where gits is called
COMMAND='GITS_URL_START="~/.gits/events/home.sh" GITS_URL_END="relative.sh" gits url > /dev/null 2>&1; echo "exit code ${?}"; cat "${LOG}"'
EXPECTED_STDOUT="exit code 0
GITS_URL_START (env)
GITS_URL_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "path of a script: ~/ and relative to the directory where gits was called"

rm relative.sh

# ---------- GITS_SHELL ----------

# a shell which leaves a trace for every script it is asked to run, then lets bash do it
cat <<EEE > "${WORK}/myshell"
#!/bin/bash
if [[ "\${1}" != "-c" ]]; then
  echo "myshell runs \$(basename "\${1}") \${2} \${3}" >> "${LOG}"
fi
exec /bin/bash "\${@}"
EEE
chmod +x "${WORK}/myshell"
rm -f "${LOG}"

# the script is started as: $GITS_SHELL <script> <EVENT> <command>
COMMAND='GITS_SHELL="${WORK}/myshell" GITS_URL_END="${WORK}/scripts/log.sh" gits url > /dev/null 2>&1; cat "${LOG}"'
EXPECTED_STDOUT="myshell runs log.sh END url
GITS_URL_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "scripts are executed by the shell from GITS_SHELL, with the event and the command as arguments"

# ---------- isinsync stays silent on stdout ----------

cat <<'EEE' > "${WORK}/scripts/talk.sh"
echo "script talks on stdout"
echo "script talks on stderr" >&2
EEE

# stdout of isinsync belongs to nobody (it is used as: if gits isinsync; then ...):
# both lines of the script arrive on stderr
COMMAND='GITS_ISINSYNC_AFTER_COMPARE="${WORK}/scripts/talk.sh" gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR="script talks on stdout
script talks on stderr"
EXPECTED_CODE="0"
test "isinsync: what a script prints goes to stderr"

# in every other command stdout of a script is stdout
COMMAND='GITS_URL_END="${WORK}/scripts/talk.sh" gits url 2> /dev/null | has "script talks on stdout" "script talks on stderr"'
EXPECTED_STDOUT="script talks on stdout"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "other commands: stdout of a script is stdout"

# ---------- scripts defined in the config of the project ----------

# The config is a shell script: it can define the same variables. Here two of them, one with
# a path relative to the root of the project (where gits is called).
cp "${WORK}/scripts/log.sh" .git/project-event.sh
cat <<EEE > .git/gits.sh
GITS_TARGETDIR="${D}"
GITS_LIST=(
    "gits.sh::\$GITS_TARGETDIR/gits.sh"
    "../file.txt::\$GITS_TARGETDIR/file.txt"
)

GITS_DIFF_AFTER_COMPARE="${WORK}/scripts/log.sh"
GITS_DIFF_ALL=".git/project-event.sh"
EEE
rm -f "${LOG}"

# GITS_DIFF_START is from the environment. The config is known only after it was executed:
# its GITS_DIFF_ALL runs for CONFIG_LOADED and everything after it, not for START.
# For AFTER_COMPARE: the script of the event first, then the one of GITS_DIFF_ALL.
COMMAND='GITS_DIFF_START="${WORK}/scripts/log.sh" gits diff > /dev/null 2>&1; echo "exit code ${?}"; cat "${LOG}"'
EXPECTED_STDOUT="exit code 1
GITS_DIFF_START (env)
GITS_DIFF_CONFIG_LOADED (config)
GITS_DIFF_BEFORE_CLONE (config)
GITS_DIFF_AFTER_CLONE (config)
GITS_DIFF_BEFORE_COPY (config)
GITS_DIFF_AFTER_COPY (config)
GITS_DIFF_BEFORE_COPY (config)
GITS_DIFF_AFTER_COPY (config)
GITS_DIFF_BEFORE_COMPARE (config)
GITS_DIFF_AFTER_COMPARE (config)
GITS_DIFF_AFTER_COMPARE (config)
GITS_DIFF_BEFORE_CLEANUP (config)
GITS_DIFF_AFTER_CLEANUP (config)
GITS_DIFF_END (config)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "scripts defined in .git/gits.sh run from CONFIG_LOADED on"

rm -f "${LOG}"

# the same event defined in the environment AND in the config: both run, the environment first.
# A variable the config only inherited from the environment is not "defined by the config":
# GITS_DIFF_END runs once.
COMMAND='GITS_DIFF_AFTER_COMPARE="${WORK}/scripts/fail.sh" GITS_DIFF_END="${WORK}/scripts/log.sh" gits diff > /dev/null 2>&1; grep -E "AFTER_COMPARE|GITS_DIFF_END" "${LOG}"'
EXPECTED_STDOUT="GITS_DIFF_AFTER_COMPARE (env) FAILS
GITS_DIFF_AFTER_COMPARE (config)
GITS_DIFF_AFTER_COMPARE (config)
GITS_DIFF_END (env)
GITS_DIFF_END (config)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the same event in the environment and in the config: both run, the environment first"

# a second project without scripts in its config, next to the first one
cd ..
project plain "git@github.com:tmp/plain.git"
echo 'p' > plain/file.txt
cat <<'EEE' > plain/.git/gits.sh
GITS_TARGETDIR="git@github.com:tmp__plain.git"
GITS_LIST=(
    "../file.txt::$GITS_TARGETDIR/file.txt"
)
EEE
(cd plain && gits push --yes > /dev/null 2>&1) || fail "push of the second project failed"

# the first project gets scripts for state
cat <<EEE >> repo/.git/gits.sh
GITS_STATE_AFTER_COMPARE="${WORK}/scripts/log.sh"
EEE
rm -f "${LOG}"

# state checks ./plain and ./repo. The script of the config of repo runs only while repo is
# checked: one line in the log, not two.
COMMAND='gits state > /dev/null 2>&1; cat "${LOG}"'
EXPECTED_STDOUT="GITS_STATE_AFTER_COMPARE (config)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: the scripts of a config run only for the project of that config"

# ---------- the replaceable event FIND ----------

# never entered by the default script
project node_modules/pkg "git@github.com:tmp/pkg.git"
cp plain/.git/gits.sh node_modules/pkg/.git/gits.sh

COMMAND='gits find'
EXPECTED_STDOUT="./plain
./repo"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "FIND, the default script (events/defaults/FIND.sh): node_modules is not entered"

# a script of the user: it decides what is looked at. It prints config files, one per line,
# also one which doesn't exist and a line which is not a config: both are ignored.
cat <<'EEE' > "${WORK}/scripts/find.sh"
echo "event ${1} of ${2} in ${3}, GITS_EVENT=${GITS_EVENT}" >> "${LOG}"
echo "./node_modules/pkg/.git/gits.sh"
echo "./repo/.git/gits.sh"
echo "./nothing/.git/gits.sh"
echo "not a config at all"
EEE
rm -f "${LOG}"

COMMAND='GITS_FIND_FIND="${WORK}/scripts/find.sh" gits find; cat "${LOG}"'
EXPECTED_STDOUT="./node_modules/pkg
./repo
event FIND of find in ${WORK}, GITS_EVENT=GITS_FIND_FIND"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "FIND replaced by GITS_FIND_FIND: its list is used, what is not a real config is ignored"

# the variable of another command doesn't count: GITS_FIND_FIND is not used by state
COMMAND='GITS_FIND_FIND="${WORK}/scripts/find.sh" gits state 2>&1 | has "1 : 2 >./plain/.git/gits.sh<" "2 : 2 >./repo/.git/gits.sh<"'
EXPECTED_STDOUT="1 : 2 >./plain/.git/gits.sh<
2 : 2 >./repo/.git/gits.sh<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "GITS_FIND_FIND is the event of 'gits find' only: state uses the default"

COMMAND='GITS_STATE_FIND="${WORK}/scripts/find.sh" gits state 2>&1 | has "1 : 2 >./node_modules/pkg/.git/gits.sh<" "2 : 2 >./repo/.git/gits.sh<" "plain"'
EXPECTED_STDOUT="1 : 2 >./node_modules/pkg/.git/gits.sh<
2 : 2 >./repo/.git/gits.sh<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "FIND replaced by GITS_STATE_FIND: state checks what the script printed"

# the search is a part of the command: when its script fails, the command fails
COMMAND='GITS_FIND_FIND="${WORK}/scripts/fail.sh" gits find 2>&1 | has "of event GITS_FIND_FIND ended with exit code 7"'
EXPECTED_STDOUT="of event GITS_FIND_FIND ended with exit code 7"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "FIND script fails: an error of the command"

# GITS_ALL is not called for FIND (it could not print the list), but for the events around it
rm -f "${LOG}"
COMMAND='GITS_ALL="${WORK}/scripts/log.sh" gits find > /dev/null; cat "${LOG}"'
EXPECTED_STDOUT="GITS_FIND_START (env)
GITS_FIND_FOUND (env)
GITS_FIND_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "GITS_ALL is not called for the replaceable event FIND"

rm -rf node_modules

# ---------- gits called from inside of a script ----------

# The script of END calls gits itself. GITS_ALL is inherited by that inner gits, but the inner
# one sees GITS_EVENT_RUNNING and runs no scripts: the log has the events of the outer run only.
cat <<EEE > "${WORK}/scripts/nested.sh"
echo "\${GITS_EVENT} of the outer gits, calling gits find:" >> "\${LOG}"
"${BIN}" find >> "\${LOG}" 2>&1
EEE
rm -f "${LOG}"

COMMAND='cd repo && GITS_URL_END="${WORK}/scripts/nested.sh" GITS_ALL="${WORK}/scripts/log.sh" gits url > /dev/null 2>&1; cat "${LOG}"'
EXPECTED_STDOUT="GITS_URL_START (env)
GITS_URL_CONFIG_LOADED (env)
GITS_URL_END of the outer gits, calling gits find:
.
GITS_URL_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "gits called from a script runs no scripts itself"

# ---------- the names from before the rename ----------

STORAGE="${GITS_SOURCE}"
unset GITS_SOURCE

COMMAND='gits find 2>&1 | has "env var GITS_SOURCE is not defined or empty"'
EXPECTED_STDOUT="env var GITS_SOURCE is not defined or empty"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "without GITS_SOURCE: the error names the new variable"

# the old name of the storage is read when the new one is not defined, --help says where the value is from
COMMAND='GITSTORAGESOURCE="${STORAGE}" gits --help | grep "^  GITS_SOURCE  *|" | tr -s " "'
EXPECTED_STDOUT=" GITS_SOURCE | ${STORAGE} (from GITSTORAGESOURCE) | (none) | ${STORAGE}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "GITSTORAGESOURCE is still read, --help shows where the value came from"

export GITS_SOURCE="${STORAGE}"

# the new name wins when both are defined
COMMAND='GITSTORAGESOURCE="${WORK}/nothing-here" gits find'
EXPECTED_STDOUT="./plain
./repo"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "both names defined: the new one wins"

# a config written with the old names of the two variables
cd plain
cat <<'EEE' > .git/gits.sh
GITSTORAGETARGETDIR="git@github.com:tmp__plain.git"
GITSTORAGELIST=(
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
)
EEE

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a config with GITSTORAGETARGETDIR / GITSTORAGELIST still works"

# add keeps the style of the config: the new line uses the variable the config defines
echo 'more' > more.txt
COMMAND='gits add more.txt > /dev/null 2>&1; cat .git/gits.sh'
EXPECTED_STDOUT='GITSTORAGETARGETDIR="git@github.com:tmp__plain.git"
GITSTORAGELIST=(
    "../file.txt::$GITSTORAGETARGETDIR/file.txt"
    "../more.txt::$GITSTORAGETARGETDIR/more.txt"
)'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add to a config with the old names: the old variable is used in the new line"

# migrate in a project which has gits.sh already: the variables get their new names
COMMAND='gits migrate 2>&1 | has "variables renamed"; cat .git/gits.sh; gits migrate'
EXPECTED_STDOUT='variables renamed
GITS_TARGETDIR="git@github.com:tmp__plain.git"
GITS_LIST=(
    "../file.txt::$GITS_TARGETDIR/file.txt"
    "../more.txt::$GITS_TARGETDIR/more.txt"
)
nothing to migrate: .git/gits.sh is already here'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "gits migrate renames the variables of a config, once"

# the shell: the old name is read too
rm -f "${LOG}"
COMMAND='GITSTORAGETESHELL="${WORK}/myshell" GITS_URL_END="${WORK}/scripts/log.sh" gits url > /dev/null 2>&1; cat "${LOG}"'
EXPECTED_STDOUT="myshell runs log.sh END url
GITS_URL_END (env)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "GITSTORAGETESHELL is still read"

cd ..

# ---------- gits events ----------

# every event of every command with a line saying when it fires; a defined variable shows its value
COMMAND='GITS_PUSH_BEFORE_PUSH="~/check.sh" GITS_ALL="/x/all.sh" gits events | grep -E "^  (GITS_ALL|GITS_PUSH_BEFORE_PUSH|GITS_PUSH_AFTER_PUSH|GITS_STATE_FIND|GITS_UPDATE_ALL) " | tr -s " "'
EXPECTED_STDOUT=" GITS_ALL /x/all.sh
 GITS_STATE_FIND - (replaces a default)
 GITS_PUSH_BEFORE_PUSH ~/check.sh (can stop the command)
 GITS_PUSH_AFTER_PUSH -
 GITS_UPDATE_ALL -"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "gits events: the list, the defined ones with their value"

# it needs neither the storage nor a project
COMMAND='(unset GITS_SOURCE; cd / && "${BIN}" events | grep -c "^  GITS_")'
EXPECTED_STDOUT="133"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "gits events works without GITS_SOURCE: 133 variables"

# events/examples/ in the repository is generated: it has to be what the binary writes
COMMAND='gits events --examples "${WORK}/examples" && diff -r "${WORK}/examples" "${_ROOT}/events/examples" && ls "${WORK}/examples" | wc -l | tr -d " "'
EXPECTED_STDOUT="133 example scripts written to ${WORK}/examples
133"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "events/examples/ is up to date with 'gits events --examples'"

# an example script is a working script: registered as it is, it runs and prints its line
COMMAND='cd repo && GITS_URL_END="${_ROOT}/events/examples/GITS_URL_END.sh" gits url 2>&1 | has "[3] GITS_URL_END #1: 0"'
EXPECTED_STDOUT="[3] GITS_URL_END #1: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "an example script works as it is"

# the example of the replaceable event is a working replacement
COMMAND='GITS_FIND_FIND="${_ROOT}/events/examples/GITS_FIND_FIND.sh" gits find'
EXPECTED_STDOUT="./plain
./repo"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the example script of FIND works as a replacement"

COMMAND='gits events --what 2>&1 | has "usage: gits events"'
EXPECTED_STDOUT="usage: gits events"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "gits events with an unknown argument"
