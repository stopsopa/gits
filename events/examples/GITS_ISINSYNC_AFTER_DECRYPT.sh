#
# Example script of the lifecycle event GITS_ISINSYNC_AFTER_DECRYPT   (gits isinsync, event AFTER_DECRYPT)
#
# When:
#   that file was decrypted (or turned out to be stored not encrypted)
#   Fired: once per encrypted element whose file is in the storage.
#
# This script can't stop the command: a non-zero exit code is only reported as a warning.
#
# Register it (the value is the path of the script, ~/ means your home):
#
#   export GITS_ISINSYNC_AFTER_DECRYPT="~/.gits/events/GITS_ISINSYNC_AFTER_DECRYPT.sh"        in ~/.zshrc or ~/.bashrc
#   GITS_ISINSYNC_AFTER_DECRYPT="~/.gits/events/GITS_ISINSYNC_AFTER_DECRYPT.sh"               or in .git/gits.sh of a project
#
# It is executed by the shell from GITS_SHELL (default /bin/bash), in the directory where
# gits was called:
#
#   $GITS_SHELL <this script> AFTER_DECRYPT isinsync "<local file (absolute)>" "<file in the temporary clone>"
#
# Arguments:
#   $1   AFTER_DECRYPT
#   $2   isinsync
#   $3   local file (absolute)
#   $4   file in the temporary clone
#
# Env vars of this event:
#   GITS_EVENT_FILE_SOURCE       the local file, absolute path
#   GITS_EVENT_FILE_SOURCE_RAW   SOURCE as it is written in the config
#   GITS_EVENT_FILE_TARGET       TARGET: path of the file in the storage
#   GITS_EVENT_FILE_STORED       the file in the temporary clone, absolute path
#   GITS_EVENT_FILE_ENCRYPTED    1 for SOURCE:e:TARGET, 0 for SOURCE::TARGET
#   GITS_EVENT_FILE_INDEX        position of the element in GITS_LIST, from 1
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

echo "[${GITS_EVENT_SEQ}] ${GITS_EVENT} #${GITS_EVENT_INDEX}: ${3} ${4}"
