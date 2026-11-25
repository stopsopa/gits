#
# The interactive list of "gits add": in a terminal the found files are shown first, each one
# can be ticked (column "add") and marked as encrypted (column "enc"), and the config is written
# only after ctrl+enter. (tests/test006 covers "gits add" without a terminal: no list at all.)
#
# The list shows up only when stdin and stdout are a terminal, so every "gits add" here runs
# through tests/terminal.py: it starts gits in a pseudo terminal (80 x 24) and presses the keys
# given as its first argument, e.g. "DOWN SPACE RIGHT CTRL_ENTER". It prints what gits printed
# after the list was closed, or with SCREEN=1 the last screen of the list, without colors.
#
# What is tested, in this order:
#
#   1. the screen: one row per file with its relative path, files which are in the config
#      already are not listed (only counted), everything is ticked at the beginning, and the
#      paths are in one column also in a row without the box "enc"
#   2. Enter alone writes nothing
#   3. arrows + space: unticking a file, marking another one as encrypted ("SOURCE:e:TARGET")
#   4. space on "enc" of a row which is not ticked ticks both
#   5. shortcuts of the column "add": n (none), a (all), i (invert)
#   6. shortcuts of the column "enc": A (all), N (none), I (invert), only among the ticked rows
#   7. "gits add -e": everything is marked as encrypted at the beginning
#   8. the other ways of saying ctrl+enter: modifyOtherKeys of xterm, ctrl+j, ctrl+s
#   9. ctrl+enter with nothing ticked writes nothing
#  10. leaving: q and Esc (exit code 1), Ctrl+C (exit code 130): the config is not touched
#  11. stdin which is not a terminal (echo "" | gits add ...), in a terminal: no list,
#      everything is added. "gits add --yes" is refused
#
# Needs: the compiled binary (/bin/bash compile.sh) and python3 (only for tests/terminal.py).
#
# /bin/bash tests/test014/test.sh
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
# ":?" stops the script when _DIR is empty, instead of touching /tmp
if [[ -d "${_DIR:?}/tmp" ]]; then
  chmod -R u+w "${_DIR:?}/tmp"
  rm -rf "${_DIR:?}/tmp"
fi

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, function "test" and the helpers used here (project, has, fail)
source "${_DIR}/../_lib.sh"

if ! command -v python3 > /dev/null 2>&1; then
  fail "python3 is not installed, tests/terminal.py needs it"
fi

# keys <keys> <arguments of gits>
# gits in a pseudo terminal, with the keys pressed in it
function keys {
  local KEYS="${1}"
  shift
  python3 "${_ROOT}/tests/terminal.py" "${KEYS}" "${BIN}" "${@}"
}

# the lines of the list in the config, without the indentation: what a check looks at
function list {
  grep '^ *"' .git/gits.sh | sed 's/^ *//'
}

# the config every check starts from: one of the four files of "dir" is registered already
function config {
  cat <<'EEE' > .git/gits.sh
GITS_TARGETDIR="git@github.com:tmp__repo.git"

GITS_LIST=(
    "gits.sh::$GITS_TARGETDIR/gits.sh"
    "../dir/a.txt::$GITS_TARGETDIR/dir/a.txt"
)
EEE
}

# a project with files to choose from; everything below runs in it
project repo "git@github.com:tmp/repo.git"
cd repo
mkdir -p dir/sub
echo "a" > dir/a.txt
echo "b" > dir/b.txt
echo "c" > dir/c.txt
echo "d" > dir/sub/d.txt
echo "KEY=1" > .env

# the two lines of the config which are there before every check
L0='"gits.sh::$GITS_TARGETDIR/gits.sh"
"../dir/a.txt::$GITS_TARGETDIR/dir/a.txt"'

# ---------- 1. the screen ----------

# "gits add dir .env" finds 5 files, dir/a.txt is in the config: 4 rows and "(1 already in the config)".
# Keys: DOWN (cursor to dir/c.txt), SPACE (untick it), then q to leave. SCREEN=1 prints the last
# screen. Looked for, as whole fragments with their spaces:
#   - the title with the counters
#   - the header of the columns
#   - a ticked row: both boxes
#   - the row under the cursor (">"), not ticked: no box "enc", and the path starts in the
#     same column as in the other rows
#   - a file in a subdirectory and a file given directly, with paths relative to the project
# Exit code 1: the list was left with q.
config
COMMAND='SCREEN=1 keys "DOWN SPACE q" add dir .env 2>&1 | has "gits add: 4 found, 3 ticked, 0 encrypted   (1 already in the config)" "    add enc  file" "    [x] [ ]  dir/b.txt" "  > [ ]      dir/c.txt" "    [x] [ ]  dir/sub/d.txt" "    [x] [ ]  .env" "ctrl+enter: add the ticked files"'
EXPECTED_STDOUT='gits add: 4 found, 3 ticked, 0 encrypted   (1 already in the config)
    add enc  file
    [x] [ ]  dir/b.txt
  > [ ]      dir/c.txt
    [x] [ ]  dir/sub/d.txt
    [x] [ ]  .env
ctrl+enter: add the ticked files'
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "the screen: rows, columns, counters"

# The file which is registered already is not offered again.
COMMAND='SCREEN=1 keys "q" add dir .env 2>&1 | has "dir/a.txt"'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "a registered file is not in the list"

# ---------- 2. Enter alone ----------

# ENTER: the list stays open and says what to press (SCREEN=1 shows that message), q leaves.
config
COMMAND='SCREEN=1 keys "ENTER q" add dir .env 2>&1 | has "Enter alone does nothing: ctrl+enter adds the ticked files"; list'
EXPECTED_STDOUT="Enter alone does nothing: ctrl+enter adds the ticked files
${L0}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "Enter alone writes nothing"

# ---------- 3. arrows and space ----------

# The cursor starts on the box "add" of the first row (dir/b.txt).
#   DOWN SPACE         dir/c.txt is unticked
#   DOWN RIGHT SPACE   dir/sub/d.txt: the cursor goes to the box "enc", it is ticked
#   CTRL_ENTER         write
# gits prints the added lines and exits with 0; then the list of the config: 3 new lines after
# the 2 old ones, in the order of the list, dir/c.txt is not there, dir/sub/d.txt is with ":e:".
config
COMMAND='keys "DOWN SPACE DOWN RIGHT SPACE CTRL_ENTER" add dir .env 2>&1 | has "added lines: 3"; list'
EXPECTED_STDOUT="added lines: 3
${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/sub/d.txt:e:$GITS_TARGETDIR/dir/sub/d.txt"
"../.env::$GITS_TARGETDIR/.env"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "untick one file, encrypt another"

# The same keys, only the exit code of gits itself (0 after ctrl+enter).
config
COMMAND='keys "DOWN SPACE DOWN RIGHT SPACE CTRL_ENTER" add dir .env > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "exit code after ctrl+enter"

# LEFT goes back to the box "add": RIGHT LEFT SPACE unticks the first file instead of encrypting it.
# UP on the first row and DOWN on the last one stay there: END DOWN SPACE unticks the last file (.env).
config
COMMAND='keys "RIGHT LEFT SPACE UP END DOWN SPACE CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/c.txt::$GITS_TARGETDIR/dir/c.txt"
"../dir/sub/d.txt::$GITS_TARGETDIR/dir/sub/d.txt"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "left, and the ends of the list"

# ---------- 4. "enc" of a row which is not ticked ----------

#   n             nothing is ticked
#   RIGHT SPACE   box "enc" of dir/b.txt, which has no box now: the file is ticked and encrypted
config
COMMAND='keys "n RIGHT SPACE CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt:e:$GITS_TARGETDIR/dir/b.txt"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "enc on a row which is not ticked ticks both"

# ---------- 5. shortcuts of the column "add" ----------

#   n            all off
#   DOWN SPACE   only dir/c.txt on
#   i            invert: everything but dir/c.txt
config
COMMAND='keys "n DOWN SPACE i CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/sub/d.txt::$GITS_TARGETDIR/dir/sub/d.txt"
"../.env::$GITS_TARGETDIR/.env"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add column: none, invert"

#   n a   all off, then all on: the four files
config
COMMAND='keys "n a CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/c.txt::$GITS_TARGETDIR/dir/c.txt"
"../dir/sub/d.txt::$GITS_TARGETDIR/dir/sub/d.txt"
"../.env::$GITS_TARGETDIR/.env"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add column: all"

# ---------- 6. shortcuts of the column "enc" ----------

#   SPACE   dir/b.txt is unticked
#   A       encrypt all: only the three ticked rows, the unticked one gets nothing
#   SPACE   dir/b.txt is ticked again: plain
config
COMMAND='keys "SPACE A SPACE CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/c.txt:e:$GITS_TARGETDIR/dir/c.txt"
"../dir/sub/d.txt:e:$GITS_TARGETDIR/dir/sub/d.txt"
"../.env:e:$GITS_TARGETDIR/.env"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "enc column: all, only among the ticked rows"

#   RIGHT SPACE   dir/b.txt encrypted
#   I             invert: dir/b.txt plain, the three others encrypted
config
COMMAND='keys "RIGHT SPACE I CTRL_ENTER" add dir .env > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/c.txt:e:$GITS_TARGETDIR/dir/c.txt"
"../dir/sub/d.txt:e:$GITS_TARGETDIR/dir/sub/d.txt"
"../.env:e:$GITS_TARGETDIR/.env"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "enc column: invert"

#   A N   all encrypted, then none: no line with ":e:" (has prints nothing), 6 lines in the list
config
COMMAND='keys "A N CTRL_ENTER" add dir .env > /dev/null 2>&1; list | has ":e:"; list | wc -l | tr -d " "'
EXPECTED_STDOUT="6"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "enc column: none"

# ---------- 7. gits add -e ----------

# With -e every row starts ticked and encrypted (the title of the first screen says so).
config
COMMAND='SCREEN=1 keys "q" add -e dir .env 2>&1 | has "gits add: 4 found, 4 ticked, 4 encrypted"'
EXPECTED_STDOUT="gits add: 4 found, 4 ticked, 4 encrypted"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "add -e: everything starts as encrypted"

#   RIGHT SPACE   dir/b.txt: encryption off, the rest stays encrypted
config
COMMAND='keys "RIGHT SPACE CTRL_ENTER" add -e dir > /dev/null 2>&1; list'
EXPECTED_STDOUT="${L0}"'
"../dir/b.txt::$GITS_TARGETDIR/dir/b.txt"
"../dir/c.txt:e:$GITS_TARGETDIR/dir/c.txt"
"../dir/sub/d.txt:e:$GITS_TARGETDIR/dir/sub/d.txt"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add -e: one file made plain"

# ---------- 8. other ways of saying ctrl+enter ----------

# CTRL_ENTER above is what a terminal with the kitty keyboard protocol sends. Three more:
# what xterm sends with modifyOtherKeys, and ctrl+j and ctrl+s for terminals which can't tell
# ctrl+enter from Enter at all. Each one adds the only file given.
for KEY in CTRL_ENTER_X CTRL_J CTRL_S; do
  config
  COMMAND='keys "${KEY}" add .env > /dev/null 2>&1; list'
  EXPECTED_STDOUT="${L0}"'
"../.env::$GITS_TARGETDIR/.env"'
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "written after ${KEY}"
done

# ---------- 9. nothing ticked ----------

# n CTRL_ENTER: there is nothing to write, the list stays open and says so; q leaves.
config
COMMAND='SCREEN=1 keys "n CTRL_ENTER q" add dir .env 2>&1 | has "no file is ticked"; list'
EXPECTED_STDOUT="no file is ticked
${L0}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "ctrl+enter with nothing ticked"

# ---------- 10. leaving ----------

# q: gits says that nothing was added, and the config is what it was.
config
COMMAND='keys "SPACE q" add dir .env 2>&1 | has "nothing added: the list was left without ctrl+enter"; list'
EXPECTED_STDOUT="nothing added: the list was left without ctrl+enter
${L0}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "q: nothing is written"

# Esc does the same; here only the exit code of gits: 1.
COMMAND='keys "ESC" add dir .env > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "esc: exit code 1"

# Ctrl+C: exit code 130, like an interrupted command.
COMMAND='keys "CTRL_C" add dir .env 2>&1 | has "nothing added: interrupted"'
EXPECTED_STDOUT="nothing added: interrupted"
EXPECTED_STDERR=""
EXPECTED_CODE="130"
test "ctrl+c: exit code 130"

# After Esc and Ctrl+C the config is still the one written by "config" before the check of q.
COMMAND='list'
EXPECTED_STDOUT="${L0}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "esc and ctrl+c: nothing is written"

# ---------- 11. stdin which is not a terminal ----------

# The way to say "no list" in a terminal: echo "" | gits add ...
# tests/terminal.py starts a shell in the pseudo terminal, so stdout of gits is a terminal and
# only its stdin is a pipe. No key is pressed: gits adds every found file and ends by itself.
config
export BIN
COMMAND='python3 "${_ROOT}/tests/terminal.py" "" /bin/bash -c "echo \"\" | \"\${BIN}\" add dir .env" 2>&1 | has "added lines: 4"; list | wc -l | tr -d " "'
EXPECTED_STDOUT="added lines: 4
6"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "echo | gits add: no list"

# The same with -e: without the list -e applies to every file.
config
COMMAND='python3 "${_ROOT}/tests/terminal.py" "" /bin/bash -c "echo \"\" | \"\${BIN}\" add -e dir .env" > /dev/null 2>&1; list | grep -c ":e:"'
EXPECTED_STDOUT="4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "echo | gits add -e: everything as encrypted"

# --yes belongs to push and pull. add refuses it and says what to do instead; nothing is written.
config
COMMAND='gits add --yes dir 2>&1 | has "gits add doesn'"'"'t take --yes" "echo \"\" | gits add"; list'
EXPECTED_STDOUT="gits add doesn't take --yes
echo \"\" | gits add
${L0}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "add --yes is refused"
