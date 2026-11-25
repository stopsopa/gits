#
# "gits add <path>...": registers files in the list of .git/gits.sh, and does nothing else
# (no copying, no clone of the storage, no push).
#
# What is tested, in this order:
#
# 1. Without a config: error which sends to "gits init".
# 2. Wrong arguments: no path at all, a path which doesn't exist.
# 3. A file which is already in the list (given in another spelling, ./.env): nothing is added.
# 4. One call with a directory, a file in .git, a file in home and a file outside of the project:
#    - a directory is walked and every file in it gets its own line (node_modules and .git inside
#      of it are skipped)
#    - SOURCE is written the way it is written by hand: "../x" for files of the project, "x" for files
#      in .git, "~/x" for files in home, an absolute path for the rest
#    - new lines go to the end of the list, with the indentation and the form of the variable
#      (${GITS_TARGETDIR} or $GITS_TARGETDIR) the config already uses
#    - everything else in the config (comments, empty lines, code after the list) stays as it was
#    - the storage is not touched and no file is created
#    - the same directory given again: nothing is added
# 5. The config made that way works: "gits push --yes" stores the files where the lines say.
# 6. "gits add -e": the line is written with ":e:" (encrypted element).
# 7. A config with an empty list: the default style is used (4 spaces, $GITS_TARGETDIR).
# 8. A config whose list is written in one line: add refuses and leaves the file as it was.
#
# /bin/bash tests/test006/test.sh
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

# directory of the project in the storage (GITS_TARGETDIR), made from the remote below
D="git@github.com:tmp__repo.git"

# an empty project with a remote and without any config yet; everything below runs in it
project repo "git@github.com:tmp/repo.git"
cd repo

# "gits add" has nothing to add to when .git/gits.sh doesn't exist: it doesn't create one,
# it tells to run "gits init". Exit code 1.
COMMAND='gits add file.txt 2>&1 | has "doesn'"'"'t exist, create it with: gits init"'
EXPECTED_STDOUT="doesn't exist, create it with: gits init"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add without config"

# The config "gits add" will work on. Written with details which have to survive:
#   - indentation of 2 spaces and the variable in the form ${GITS_TARGETDIR}: new lines
#     have to follow both
#   - a comment above the list, a comment and an empty line inside of the list
#   - code after the list (echo): the new lines must go into the list, not to the end of the file
# It already has two elements: the config itself and ../.env
cat <<EEE > .git/gits.sh
#!/bin/bash

GITS_TARGETDIR="${D}"

# list
GITS_LIST=(
  "gits.sh::\${GITS_TARGETDIR}/gits.sh"

  # keep me
  "../.env::\${GITS_TARGETDIR}/.env"
)

echo "after the list"
EEE

# The files which will be given to "gits add":
#   .env                          already in the list
#   .git/xx.ts                    a file in .git                  -> SOURCE "xx.ts"
#   dir/a.txt                     files in a directory            -> SOURCE "../dir/..."
#   dir/sub dir/b c.txt           (spaces in the directory and in the name)
#   dir/node_modules/..., dir/.git/...   must be skipped when "dir" is walked
#   ~/.zshrc                      a file in home (HOME of the test) -> SOURCE "~/.zshrc"
#   ${WORK}/elsewhere/e.txt       a file outside of the project and outside of home -> absolute SOURCE
echo "E=1" > .env
echo "xx" > .git/xx.ts
mkdir -p "dir/sub dir" dir/node_modules/pkg dir/.git
echo "a" > dir/a.txt
echo "b" > "dir/sub dir/b c.txt"
echo "ignored" > dir/node_modules/pkg/index.js
echo "ignored" > dir/.git/config
echo "z" > "${HOME}/.zshrc"
mkdir -p "${WORK}/elsewhere"
echo "e" > "${WORK}/elsewhere/e.txt"

# ---------- wrong arguments ----------

# "gits add" needs at least one path: without it the usage is printed, exit code 1.
COMMAND='gits add 2>&1 | has "usage: gits add"'
EXPECTED_STDOUT="usage: gits add"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add without path"

# A path which is neither a file nor a directory: error which names the path the way it was given
# (between > and <), exit code 1.
COMMAND='gits add nothing.txt 2>&1 | has ">nothing.txt< is neither a file nor a directory"'
EXPECTED_STDOUT=">nothing.txt< is neither a file nor a directory"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add of a path which doesn't exist"

# ---------- already there (the same file, written another way) ----------

# the config before the next call, to compare with
BEFORE="$(cat .git/gits.sh)"

# .env is already in the list as "../.env". It is given as "./.env": gits compares the files the
# paths point to, not the text. "nothing added", exit code 0, and the config (printed by cat) is
# exactly what it was before.
COMMAND='gits add ./.env 2>&1 | has "nothing added"; cat .git/gits.sh'
EXPECTED_STDOUT="nothing added
${BEFORE}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add of a registered file changes nothing"

# ---------- a directory, a file in .git, a file in home, a file elsewhere, all in one call ----------

# Four paths in one call. 5 lines are added: 2 files found in "dir" (a.txt and "sub dir/b c.txt";
# node_modules and .git inside of it are not walked) + xx.ts + .zshrc + e.txt.
# The second fragment is the reminder that only the config was changed and nothing was pushed.
COMMAND='gits add dir .git/xx.ts ~/.zshrc "${WORK}/elsewhere/e.txt" 2>&1 | has "added lines: 5" "only the config was changed"'
EXPECTED_STDOUT="added lines: 5
only the config was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add: number of lines, reminder"

# indentation and \${...} form are the ones the config already uses; ${WORK:1} = path without the first /
# The whole config after that call:
#   - the 5 new lines are at the end of the list, before ")", in the order they were given
#   - each with the indentation (2 spaces) and the form \${GITS_TARGETDIR} the config already uses
#   - SOURCE: "../dir/..." for files of the project, "xx.ts" for the file in .git, "~/.zshrc" for the
#     file in home, the absolute path for the file elsewhere
#   - TARGET: the same relative path inside of the directory of the project in the storage; for the
#     file elsewhere it is its absolute path without the first "/" (that is what ${WORK:1} gives)
#   - the shebang, both comments, the empty line in the list and the echo after it are still there
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="#!/bin/bash

GITS_TARGETDIR=\"${D}\"

# list
GITS_LIST=(
  \"gits.sh::\${GITS_TARGETDIR}/gits.sh\"

  # keep me
  \"../.env::\${GITS_TARGETDIR}/.env\"
  \"../dir/a.txt::\${GITS_TARGETDIR}/dir/a.txt\"
  \"../dir/sub dir/b c.txt::\${GITS_TARGETDIR}/dir/sub dir/b c.txt\"
  \"xx.ts::\${GITS_TARGETDIR}/xx.ts\"
  \"~/.zshrc::\${GITS_TARGETDIR}/.zshrc\"
  \"${WORK}/elsewhere/e.txt::\${GITS_TARGETDIR}/${WORK:1}/elsewhere/e.txt\"
)

echo \"after the list\""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "config after add"

# "gits add" only edits the config: the storage still has 0 commits, and the directory of the
# project has what it had (no temporary clone left, nothing copied in).
COMMAND='storage_commits; listing'
EXPECTED_STDOUT="0
.env .git dir"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add doesn't push and creates nothing"

# The same directory once more: both files found in it are already in the list, nothing is added, exit code 0.
COMMAND='gits add dir 2>&1 | has "nothing added: all 2 file(s) are already"'
EXPECTED_STDOUT="nothing added: all 2 file(s) are already"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second add of the same directory"

# ---------- the result is a working config ----------

# The config edited by "gits add" is still a working config: push succeeds (exit code 0). The
# fragment is what the echo at the end of the config prints: the config was executed to its end
# and its output is shown.
COMMAND='gits push --yes 2>&1 | has "after the list"'
EXPECTED_STDOUT="after the list"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the config made by add, output of the config is shown"

# The content of three files as they are in the storage now, each at the TARGET "gits add" wrote:
# the one with spaces ("b"), the one from home ("z"), the one from elsewhere ("e").
COMMAND='stored "${D}/dir/sub dir/b c.txt"; stored "${D}/.zshrc"; stored "${D}/${WORK:1}/elsewhere/e.txt"'
EXPECTED_STDOUT="b
z
e"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored files: with spaces, from home, from elsewhere"

# ---------- -e: registered as encrypted ----------

# a new file, to be registered as encrypted
echo "secret" > secret.txt

# the line "gits add -e" has to write, together with the ")" after it: it is the last line of the list
# and the separator is ":e:" instead of "::"
F1="  \"../secret.txt:e:\${GITS_TARGETDIR}/secret.txt\"
)"

# "gits add -e": the output of gits is dropped, only its exit code is printed (0), and then the
# config is searched for the two lines of F1. Nothing is encrypted here and no socket is needed:
# add only writes the line.
COMMAND='gits add -e secret.txt > /dev/null 2>&1; echo "${?}"; cat .git/gits.sh | has "${F1}"'
EXPECTED_STDOUT="0
${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add -e"

# ---------- a config with the other style and an empty list ----------

# A new config in place of the previous one: no element in the list, so there is no line to
# take the indentation and the form of the variable from.
cat <<EEE > .git/gits.sh
GITS_TARGETDIR="${D}"
GITS_LIST=(
)
EEE

# "gits add" to an empty list: the line is written in the default style, 4 spaces and
# $GITS_TARGETDIR without braces (the style of "gits init").
COMMAND='gits add .env > /dev/null 2>&1; cat .git/gits.sh'
EXPECTED_STDOUT="GITS_TARGETDIR=\"${D}\"
GITS_LIST=(
    \"../.env::\$GITS_TARGETDIR/.env\"
)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add to an empty list: default style"

# ---------- a config add can't understand is left as it was ----------

# A config with the whole list in one line: there is no line with only ")" which "gits add"
# looks for to put the new lines above it.
echo 'GITS_LIST=("a::b")' > .git/gits.sh

# "gits add" doesn't guess: it says that it can't find the end of the list, exit code 1.
COMMAND='gits add .env 2>&1 | has "can'"'"'t find the end of GITS_LIST"'
EXPECTED_STDOUT="can't find the end of GITS_LIST"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add to a config in one line"

# And the config is byte for byte what it was: a refused add writes nothing.
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT='GITS_LIST=("a::b")'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add to a config in one line changes nothing"
