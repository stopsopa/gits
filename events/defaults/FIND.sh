#
# Default script of the replaceable lifecycle event FIND:
#
#   GITS_STATE_FIND      gits state          which projects to check
#   GITS_FIND_FIND       gits find           which projects to list
#   GITS_MIGRATE_FIND    gits migrate all    which projects to look at
#
# It finds the projects below a directory. gits runs it when the variable of the event is
# not defined. This file is compiled into the binary (src/events.rs), so changing it here
# changes the default only after gits is compiled again. To use another way of finding without
# compiling, point the variable to your own script:
#
#   export GITS_STATE_FIND="~/.gits/events/GITS_STATE_FIND.sh"
#
# (events/examples/GITS_STATE_FIND.sh is a starting point.)
#
# What it has to do: print the path of every config file of gits, one per line:
#
#   ./a/.git/gits.sh
#   ./b/c/.git/gitstorage-config.sh        (config of the old tool, gits migrates it when needed)
#
# gits takes the project of each line (the directory which holds that .git), sorts them and
# removes duplicates, so the order of the lines doesn't matter. Lines which are not a path ending
# with /.git/gits.sh or /.git/gitstorage-config.sh are ignored.
#
# What this default does:
#   - directories named node_modules are never entered (huge, and never a project of yours)
#   - symbolic links are not followed
#   - a ".git" which is a file (git worktree, submodule) is not a project: it holds no config
#
# How it is called (by the shell from GITS_SHELL, in the directory where gits was called):
#
#   $GITS_SHELL <script> FIND <command> "<directory to search>"
#
# Arguments:
#   $1   FIND
#   $2   the command: state, find or migrate
#   $3   directory to search (the directory where gits was called)
#
# Env vars: the ones of every event, see LIFECYCLE.md or any script in events/examples/:
#   GITS_EVENT (GITS_STATE_FIND, ...), GITS_EVENT_NAME (FIND), GITS_EVENT_COMMAND, GITS_EVENT_SEQ,
#   GITS_EVENT_INDEX, GITS_EVENT_PWD, GITS_EVENT_ARGS, GITS_EVENT_BIN, GITS_EVENT_VERSION,
#   GITS_EVENT_PID, GITS_SOURCE, GITS_SHELL, GITS_ENCRYPTION_SOCKET, GITS_TEMPLATE
#
# stdout is read by gits, stderr is shown. A non-zero exit code is an error of the command.
# GITS_<COMMAND>_ALL and GITS_ALL are not called for this event.
#

cd "${3:-.}" || exit 1

find . \
    -type d -name node_modules -prune \
    -o -type f \( -path '*/.git/gits.sh' -o -path '*/.git/gitstorage-config.sh' \) -print

# find ends with an error also when it only could not enter some directory (no permission):
# what it found is still good, the complaints are on stderr
exit 0
