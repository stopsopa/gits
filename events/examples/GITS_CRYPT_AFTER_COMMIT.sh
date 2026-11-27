#
# Example script of the lifecycle event GITS_CRYPT_AFTER_COMMIT   (gits crypt, event AFTER_COMMIT)
#
# When:
#   push --yes: the commit exists in the clone, it is not in the storage yet
#   Fired: once, only when there is something to store.
#
# This script can't stop the command: a non-zero exit code is only reported as a warning.
#
# Register it (the value is the path of the script, ~/ means your home):
#
#   export GITS_CRYPT_AFTER_COMMIT="~/.gits/events/GITS_CRYPT_AFTER_COMMIT.sh"        in ~/.zshrc or ~/.bashrc
#   GITS_CRYPT_AFTER_COMMIT="~/.gits/events/GITS_CRYPT_AFTER_COMMIT.sh"               or in .git/gits.sh of a project
#
# It is executed by the shell from GITS_SHELL (default /bin/bash), in the directory where
# gits was called:
#
#   $GITS_SHELL <this script> AFTER_COMMIT crypt "<commit hash>"
#
# Arguments:
#   $1   AFTER_COMMIT
#   $2   crypt
#   $3   commit hash
#
# Env vars of this event:
#   GITS_EVENT_COMMIT   hash of the new commit
#
# Env vars of every event:
#   GITS_EVENT                name of the variable of this event, e.g. GITS_PUSH_BEFORE_ENCRYPT (also when the script runs as *_ALL)
#   GITS_EVENT_NAME           the event, e.g. BEFORE_ENCRYPT
#   GITS_EVENT_COMMAND        the command, e.g. push
#   GITS_EVENT_SEQ            number of this event among all events of this run, from 1 (events without a script count too)
#   GITS_EVENT_INDEX          which occurrence of this event it is in this run, from 1 (BEFORE_COPY of the 3rd file: 3)
#   GITS_EVENT_TRIGGER        the variable which pointed to this script: the one of the event, GITS_<COMMAND>_ALL or GITS_ALL
#   GITS_EVENT_TRIGGER_FROM   where that variable was defined: env or config (.git/gits.sh)
#   GITS_EVENT_SCRIPT         path of this script
#   GITS_EVENT_CAN_STOP       1: a non-zero exit code of this script stops the command (START, BEFORE_*). 0: it is only reported
#   GITS_EVENT_RUNNING        1. gits started from inside of a script sees it and runs no scripts itself
#   GITS_EVENT_PWD            directory where gits was called
#   GITS_EVENT_ARGS           arguments gits was called with, separated by spaces
#   GITS_EVENT_BIN            path of the gits binary
#   GITS_EVENT_VERSION        version of gits
#   GITS_EVENT_PID            process id of gits
#   GITS_SOURCE               the storage, as gits uses it
#   GITS_SHELL                the shell which runs the config and the scripts
#   GITS_ENCRYPTION_SOCKET    socket of the encoder process (empty when not defined)
#   GITS_TEMPLATE             template of 'gits init' (empty when not defined)
#
# Env vars which exist from the moment gits knows them (empty before):
#   GITS_EVENT_PROJECT_DIR      root of the project (state: of the project which is checked right now)
#   GITS_EVENT_CONFIG           path of .git/gits.sh of the project
#   GITS_TARGETDIR              directory of the project in the storage, from the config
#   GITS_EVENT_LIST_COUNT       number of elements of GITS_LIST
#   GITS_EVENT_LIST             all elements, one per line: <e|p><TAB>local file (absolute)<TAB>TARGET   (e: encrypted, p: plain)
#   GITS_EVENT_TEMP_DIR         the temporary directory: the clone of the storage
#   GITS_EVENT_STORAGE_DIR      directory of the project inside of the clone: <temporary directory>/<GITS_TARGETDIR>
#   GITS_EVENT_STORAGE_BRANCH   branch of the storage
#   GITS_EVENT_YES              1 when --yes was given, else 0
#
# stdout and stderr of the script are shown as they come (gits isinsync: both on stderr).
# gits called from inside of this script runs no scripts itself.
#

echo "[${GITS_EVENT_SEQ}] ${GITS_EVENT} #${GITS_EVENT_INDEX}: ${3}"
