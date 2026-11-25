#
# Migration of the config of the original tool: .git/gitstorage-config.sh -> .git/gits.sh
#
# What is tested, in this order:
#
# 1. "gits migrate" in one project:
#    - the file is renamed, and inside of it only the element which stores the config itself is
#      changed ("gitstorage-config.sh::.../gitstorage-config.sh" -> "gits.sh::.../gits.sh"),
#      everything else (comments, other elements, even ones which mention gitstorage-config.sh
#      of ANOTHER project) stays as it was
#    - the old file is gone, permissions of the file (600) are kept
#    - second "gits migrate" does nothing
#    - when both files exist nothing is touched (exit code 1) and gits.sh is the one in use
#    - a directory without the old config: exit code 1
#    - unknown argument: usage, exit code 1
# 2. Automatic migration: a command which needs the config ("gits push --yes", "gits isinsync")
#    started in a project which has only the old config migrates it first, and the storage gets
#    the config under the new name.
# 3. "gits migrate all": every project below the current directory at once, with counts,
#    node_modules not entered, a project with both files reported as an error and left alone,
#    a project which already has only gits.sh not mentioned.
#
# /bin/bash tests/test005/test.sh
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

# Helper for the setup: a project the way the original tool left it.
# A git repository with remote origin git@github.com:tmp/<name>.git, one file to store (file.txt)
# and the config under the OLD name, .git/gitstorage-config.sh, with three elements:
#   - the config itself                         (this element has to be renamed by the migration)
#   - ../file.txt                               (must not be touched)
#   - the config of another project "other"     (mentions gitstorage-config.sh too, but it is not
#                                                the config of this project: must not be touched)
# chmod 600: to check later that the migration keeps the permissions.
# legacy <directory> <name>
function legacy {
  project "${1}" "git@github.com:tmp/${2}.git"
  echo "content" > "${1}/file.txt"
  cat <<EEE > "${1}/.git/gitstorage-config.sh"
#!/bin/bash

# paths will be solved from directory where gitstorage-config.sh is

GITSTORAGETARGETDIR="git@github.com:tmp__${2}.git"

GITSTORAGELIST=(
    "gitstorage-config.sh::\$GITSTORAGETARGETDIR/gitstorage-config.sh"
    "../file.txt::\$GITSTORAGETARGETDIR/file.txt"
    "../../other/.git/gitstorage-config.sh::\$GITSTORAGETARGETDIR/other/gitstorage-config.sh"
)
EEE
  chmod 600 "${1}/.git/gitstorage-config.sh"
}

# What .git/gits.sh of project "one" has to contain after the migration, byte for byte:
# the same as the old file, the only difference is the first element of the list.
# only the element of the config itself is changed
EXPECTED_BODY='#!/bin/bash

# paths will be solved from directory where gitstorage-config.sh is

GITS_TARGETDIR="git@github.com:tmp__one.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../file.txt::$GITS_TARGETDIR/file.txt"
    "../../other/.git/gitstorage-config.sh::$GITS_TARGETDIR/other/gitstorage-config.sh"
)'

# ---------- gits migrate ----------

# project "one" with the old config, all "gits migrate" checks of this section run in it
legacy one one
cd one

# The migration itself. "has" keeps from the output only the line which says what was renamed
# to what (full paths). Exit code 0: migrated.
COMMAND='gits migrate 2>&1 | has "migrated ${WORK}/one/.git/gitstorage-config.sh -> ${WORK}/one/.git/gits.sh"'
EXPECTED_STDOUT="migrated ${WORK}/one/.git/gitstorage-config.sh -> ${WORK}/one/.git/gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate"

# The new file, whole: has to be exactly EXPECTED_BODY (see above).
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate: only the element of the config itself is changed"

# Two things in one command:
#   - "listing .git | has ..." prints those of the two names which exist in .git: only "gits.sh"
#     is expected, "gitstorage-config.sh" is asked for and must NOT come back (the old file is gone)
#   - stat prints the permissions of the new file (first form is Linux, second macOS): 600, as the old one had
COMMAND='listing .git | has "gits.sh" "gitstorage-config.sh"; stat -c "%a" .git/gits.sh 2> /dev/null || stat -f "%Lp" .git/gits.sh'
EXPECTED_STDOUT="gits.sh
600"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate: old config is removed, permissions are kept"

# "gits migrate" once more in a project which is already migrated: it says so, exit code 0,
# and the file (printed by cat after it) is still exactly EXPECTED_BODY.
COMMAND='gits migrate 2>&1 | has "nothing to migrate: .git/gits.sh is already here"; cat .git/gits.sh'
EXPECTED_STDOUT="nothing to migrate: .git/gits.sh is already here
${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate again changes nothing"

# both: nothing is touched, the person has to decide
# The old file appears again next to the new one (e.g. pulled from the storage by the old tool).
# gits can't know which one is right.
echo "old" > .git/gitstorage-config.sh

# "gits migrate" with both files: refuses, tells to compare them by hand. Exit code 1: it is an error.
COMMAND='gits migrate 2>&1 | has "compare them and remove the old one by hand"'
EXPECTED_STDOUT="compare them and remove the old one by hand"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate with both configs"

# Both files after the refused migration: the old one still has "old", the new one is still EXPECTED_BODY.
COMMAND='cat .git/gitstorage-config.sh .git/gits.sh'
EXPECTED_STDOUT="old
${EXPECTED_BODY}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate with both configs: both untouched"

# Which of the two files do the other commands read? "gits diff" complains about a missing source
# file which only gits.sh lists (the config of project "other", which doesn't exist here) - the file
# with just "old" in it would give a different error. Exit code 1: a source file is missing.
COMMAND='gits diff 2>&1 | has "source file '"'"'${WORK}/other/.git/gitstorage-config.sh'"'"' doesn'"'"'t exist"'
EXPECTED_STDOUT="source file '${WORK}/other/.git/gitstorage-config.sh' doesn't exist"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "with both configs gits.sh is the one in use"

# cleaning after the "both files" case, and back to ${WORK}
rm .git/gitstorage-config.sh
cd ..

# a directory which is not a project at all: no .git, no config
mkdir empty

# "gits migrate" where there is nothing to migrate and no new config either: says so, exit code 1
# (different from "already migrated" above, which is 0).
COMMAND='cd empty && gits migrate 2>&1 | has "nothing to migrate: there is no .git/gitstorage-config.sh in the current directory"'
EXPECTED_STDOUT="nothing to migrate: there is no .git/gitstorage-config.sh in the current directory"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate, nothing there"

# The only argument "gits migrate" knows is "all": anything else prints the usage, exit code 1.
COMMAND='gits migrate what 2>&1 | has "usage: gits migrate | gits migrate all"'
EXPECTED_STDOUT="usage: gits migrate | gits migrate all"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate with unknown argument"

# ---------- automatically: any command which needs the config ----------

# Project "auto" with the old config. The config made by the helper is replaced by a shorter one
# without the element of project "other" (that file doesn't exist, push would report a missing source),
# and written with ${GITSTORAGETARGETDIR} in braces: the migration has to handle this form too.
legacy auto auto
cd auto
rm -f .git/gitstorage-config.sh
cat <<'EEE' > .git/gitstorage-config.sh
GITSTORAGETARGETDIR="git@github.com:tmp__auto.git"
GITSTORAGELIST=(
    "gitstorage-config.sh::${GITSTORAGETARGETDIR}/gitstorage-config.sh"
    "../file.txt::${GITSTORAGETARGETDIR}/file.txt"
)
EEE

# fragments expected in the output of push: F1 the migration, F2 the config copied to the clone
# of the storage under its NEW name
F1="migrated ${WORK}/auto/.git/gitstorage-config.sh -> ${WORK}/auto/.git/gits.sh"
F2="'gits.sh' -> 'git@github.com:tmp__auto.git/gits.sh'"

# "gits push --yes" in a project which has only the old config: nobody called "gits migrate",
# push migrates first and then works as usual. Exit code 0: pushed.
COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}"'
EXPECTED_STDOUT="${F1}
${F2}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the old config: migrated, stored under the new name"

# After that push:
#   - in .git only "gits.sh" exists ("gitstorage-config.sh" is asked for and must not come back)
#   - a fresh clone of the storage (${WORK}/look) has in the directory of the project exactly
#     file.txt and gits.sh: the old name never reached the storage
COMMAND='listing .git | has "gits.sh" "gitstorage-config.sh"; storage "${WORK}/look" && listing "${WORK}/look/git@github.com:tmp__auto.git"'
EXPECTED_STDOUT="gits.sh
file.txt gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "automatic migration: old config removed, storage has only the new name"

# "gits isinsync" prints nothing, exit code 0 = local files and the storage are the same
# after the migration + push.
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync after the migration"

# back to ${WORK}
cd ..

# isinsync migrates too, without a word
# project "quiet" with the old config, never pushed
legacy quiet quiet

# "gits isinsync" has to stay silent on stdout whatever it does, also when it migrates on the way
# (its messages go to stderr, dropped here). Its exit code is not looked at (nothing was pushed for
# this project, it is "not in sync"): the exit code of the command is the one of the listing after it.
# The listing shows that the migration happened: only "gits.sh" comes back.
COMMAND='cd quiet && gits isinsync 2> /dev/null; listing .git | has "gits.sh" "gitstorage-config.sh"'
EXPECTED_STDOUT="gits.sh"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync with the old config: prints nothing, migrated"

# ---------- all at once ----------

# A workspace with several projects below it, "gits migrate all" is started in ${WORK}/ws:
#   p1, deep/p2        old config only                -> have to be migrated (deep/p2: found also deeper)
#   both               old config + gits.sh ("new")   -> conflict, must be reported and left alone
#   fresh              gits.sh only                   -> nothing to do, must not be mentioned
#   node_modules/p3    old config, but in node_modules -> never entered, must stay as it is
mkdir ws
cd ws
legacy p1 p1
legacy deep/p2 p2
legacy both both
echo "new" > both/.git/gits.sh
project fresh "git@github.com:tmp/fresh.git"
echo 'GITSTORAGETARGETDIR="x"' > fresh/.git/gits.sh
legacy node_modules/p3 p3

# fragments expected in the output: F1, F2 the two migrated projects, F3 the conflict
F1="migrated ${WORK}/ws/p1/.git/gitstorage-config.sh"
F2="migrated ${WORK}/ws/deep/p2/.git/gitstorage-config.sh"
F3="both >${WORK}/ws/both/.git/gits.sh< and"

# project with the new config only (fresh) is left alone
# "gits migrate all": 2 migrated, 1 error, and because of that error exit code 1.
# "fresh" is asked for and is not in EXPECTED_STDOUT: the output must not mention that project.
COMMAND='gits migrate all 2>&1 | has "${F1}" "${F2}" "${F3}" "COUNT_SUCCESS : 2" "COUNT_ERROR   : 1" "fresh"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}
COUNT_SUCCESS : 2
COUNT_ERROR   : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "migrate all with one conflict"

# The files after "migrate all". ls gets both names for p1, deep/p2 and node_modules/p3 and prints
# only the ones which exist (errors about the others are dropped):
#   p1, deep/p2          only gits.sh                      (migrated)
#   node_modules/p3      only gitstorage-config.sh         (not entered)
# then cat: gits.sh of "both" still has "new" (the conflict was not touched).
COMMAND='ls p1/.git/gits.sh p1/.git/gitstorage-config.sh deep/p2/.git/gits.sh deep/p2/.git/gitstorage-config.sh node_modules/p3/.git/gits.sh node_modules/p3/.git/gitstorage-config.sh 2> /dev/null; cat both/.git/gits.sh'
EXPECTED_STDOUT="deep/p2/.git/gits.sh
node_modules/p3/.git/gitstorage-config.sh
p1/.git/gits.sh
new"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate all: p1 and deep/p2 migrated, node_modules is not entered, conflict untouched"

# the conflict solved by hand: the old file of "both" removed
rm both/.git/gitstorage-config.sh

# "gits migrate all" again: no old config is left below ${WORK}/ws (the one in node_modules is
# not looked for), so "nothing found" and exit code 0.
COMMAND='gits migrate all 2>&1 | has "nothing found"'
EXPECTED_STDOUT="nothing found"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "migrate all, nothing left"
