#
# The main path on one machine: a project gets its config (gits init), the files are compared
# with the storage (gits diff, gits isinsync) and stored (gits push).
#
# What is tested, in this order:
#
#   1. init in a project the storage knows nothing about: .git/gits.sh is generated from the built-in
#      template, with GITS_TARGETDIR made from the url of remote origin. A second init changes
#      nothing. The generated config works as it is.
#   2. diff when everything is new for the storage: exit code 1, content of the new files is shown,
#      the list of changed local files (absolute paths) is printed above the final url, and the
#      temporary clone made in the current directory is removed
#   3. push without --yes changes nothing; push --yes stores the files in one commit:
#      a file of the project, a file from .git, a file with a space in its name, a file from home (~/),
#      and the config itself
#   4. everything in sync: diff, isinsync and push say so and no new commit is made
#   5. one file edited: isinsync says 1, diff shows what is stored (-) and what is here (+) and lists
#      only that file
#   6. a source file which doesn't exist: diff and isinsync say "not in sync", push stores the rest
#      but ends with exit code 1, the file already stored is not removed from the storage
#   7. a storage which can't be cloned: an error (isinsync: 2), and no temporary directory is left
#   8. configs which could damage the storage or make no sense are refused: target in the root of
#      the storage, target with "..", element without a separator, empty list, no GITS_TARGETDIR
#
# Needs: the compiled binary (/bin/bash compile.sh).
#
# /bin/bash tests/test002/test.sh
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# _DIR: the directory of this file, whatever shell runs it and wherever it was called from
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

# Remove what the previous run of this test left in tests/testNNN/tmp. It is not removed at the end
# of the test, to look at it afterwards (ignored by git: .gitignore next to this file).
# chmod first: a test may leave a directory which is not writable.
if [[ -d "${_DIR}/tmp" ]]; then
  chmod -R u+w "${_DIR}/tmp"
  rm -rf "${_DIR}/tmp"
fi

# Shared setup: creates ${WORK} (= tmp/ next to this file) with an empty HOME, own git config and
# an empty storage repository in ${WORK}/GITS_SOURCE, goes to ${WORK}, and defines function "test"
# (bash/test.sh) and the helpers used below (gits, has, listing, stored, storage_commits, project, ...)
source "${_DIR}/../_lib.sh"

# Name of the directory of this project inside the storage: the url of remote origin
# (git@github.com:tmp/repo.git) with "/" replaced by "__". gits init has to come up with exactly this.
D="git@github.com:tmp__repo.git"

# An empty git repository ${WORK}/repo with remote origin: the project. The test works inside it.
project repo "git@github.com:tmp/repo.git"
cd repo

# The files which will be stored: one in the project, one with a space in its name,
# one inside .git (not seen by git of the project), and one outside of the project, in home.
echo 'test file' > test.txt
echo 'with space' > "with space.txt"
echo 'xx config' > .git/xx.ts
mkdir -p "${HOME}/.config"
echo 'from home' > "${HOME}/.config/h.conf"

# What "listing" (names in the current directory, sorted) has to print whenever gits finished:
# only the project itself. One name more would be a temporary clone which was not removed.
LISTING=".git test.txt with space.txt"

# ---------- init: nothing in the storage for this project, the built-in template is used ----------

# The storage is empty, so there is no config of this project to restore, and GITS_TEMPLATE
# is not defined: the config is generated from the template built into the binary.
COMMAND='gits init 2>&1 | has ".git/gits.sh generated (built-in template)"'
EXPECTED_STDOUT=".git/gits.sh generated (built-in template)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init"

# Three fragments which have to be in the generated config:
#   F1  GITS_TARGETDIR is the name made from remote origin
#   F2  the remote is mentioned in a comment
#   F3  the first element of the list is the config itself (written with $GITS_TARGETDIR,
#       in single quotes here so the test doesn't expand it)
F1="GITS_TARGETDIR=\"${D}\""
F2="# used in git@github.com:tmp/repo.git"
F3='"gits.sh::$GITS_TARGETDIR/gits.sh"'

# all three are found in .git/gits.sh
COMMAND='cat .git/gits.sh | has "${F1}" "${F2}" "${F3}"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init: GITS_TARGETDIR made from remote origin, remote in the comment, the config stores itself"

# init wrote only .git/gits.sh: nothing new next to the files of the project
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after init"

# the generated config, to compare with after the second init
GENERATED="$(cat .git/gits.sh)"

# init when the config is already there: it says so and ends with exit code 0, it is not an error
COMMAND='gits init 2>&1 | has "is already present - initialization not needed"'
EXPECTED_STDOUT="is already present - initialization not needed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second init"

# ... and the config is byte for byte what it was
COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="${GENERATED}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second init changes nothing"

# The generated config is used without any edit: gits reads it, clones the storage and compares.
# The config stores itself and the storage is empty, so the answer is 1 (not in sync).
# Nothing is printed, not on stdout and not on stderr.
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "the generated config works as it is: not in sync, the storage is empty"

# The config for the rest of the test, written by hand, with every kind of SOURCE:
#   gits.sh              relative: resolved from .git, so it is .git/gits.sh (the config itself)
#   xx.ts                another file in .git, target written as ${GITS_TARGETDIR} (with braces)
#   ../test.txt          a file of the project
#   ../with space.txt    spaces in SOURCE and in TARGET, and TARGET in a subdirectory
#   ~/.config/h.conf     a file from home
# Also a shebang, empty lines and a comment between the elements: the config is a shell script.
# (\$ so that the variable is written to the file as it is, ${D} is put in now.)
cat <<EEE > .git/gits.sh
#!/bin/bash

GITS_TARGETDIR="${D}"

GITS_LIST=(
    "gits.sh::\$GITS_TARGETDIR/gits.sh"
    "xx.ts::\${GITS_TARGETDIR}/xx.ts"
    "../test.txt::\$GITS_TARGETDIR/test.txt"

    # comment between elements
    "../with space.txt::\$GITS_TARGETDIR/sub dir/with space.txt"
    "~/.config/h.conf::\$GITS_TARGETDIR/home/h.conf"
)
EEE

# ---------- diff: everything is new for the storage ----------

# First diff: nothing of this project is in the storage yet. Exit code 1 = not in sync.
#   "_TARGETGITDIR: ${WORK}/repo/"   the storage is cloned to a directory inside the current one
#                                    (its random name follows, that is why the fragment ends with "/")
#   "files are not in sync"          the verdict
#   "+test file", "+from home"       files which are new for the storage are shown with their content
#   "final url ..."                  where the project is in the storage (a local directory here, not a web page)
#   "gits cleaning ${WORK}/repo/"    the temporary clone is removed at the end
COMMAND='gits diff 2>&1 | has "_TARGETGITDIR: ${WORK}/repo/" "files are not in sync" "+test file" "+from home" "final url ${GITS_SOURCE} (directory ${D})" "gits cleaning ${WORK}/repo/"'
EXPECTED_STDOUT="_TARGETGITDIR: ${WORK}/repo/
files are not in sync
+test file
+from home
final url ${GITS_SOURCE} (directory ${D})
gits cleaning ${WORK}/repo/"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "first diff: temporary directory in pwd, content of new files in the diff, url, cleaning"

# The part of the output from "changed files:" to "final url", compared exactly:
# the block with absolute paths of the local files which differ is printed just above the final url.
# Everything is new for the storage, so every file of the list is there, in the order of
# GITS_LIST: the two from .git, the two from the project, the one from home.
COMMAND='gits diff 2>&1 | sed -n "/^changed files:/,/^final url/p"'
EXPECTED_STDOUT="changed files:
  ${WORK}/repo/.git/gits.sh
  ${WORK}/repo/.git/xx.ts
  ${WORK}/repo/test.txt
  ${WORK}/repo/with space.txt
  ${HOME}/.config/h.conf

final url ${GITS_SOURCE} (directory ${D})"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "first diff: list of changed local files, also the one from home and the one with a space"

# diff left nothing behind: the temporary clone is gone
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after diff"

# The same question with isinsync: exit code 1, and not a single character printed.
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync, not in sync: prints nothing"

# ---------- push ----------

# push without --yes only looks: it says that there is something to push and how to really do it.
# Exit code 1 because the files are not in sync.
COMMAND='gits push 2>&1 | has "nothing was changed. If you are sure that you want to push them: gits push --yes"'
EXPECTED_STDOUT="nothing was changed. If you are sure that you want to push them: gits push --yes"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "push without --yes"

# ... and the storage still has no commit
COMMAND='storage_commits'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push without --yes: storage untouched"

# The real push. It prints every copied file as 'SOURCE' -> 'TARGET' (one of them is checked) and
# "files pushed" at the end. Exit code 0.
# (the '"'"' is a single quote inside of the single quoted COMMAND)
COMMAND='gits push --yes 2>&1 | has "'"'"'../test.txt'"'"' -> '"'"'${D}/test.txt'"'"'" "files pushed"'
EXPECTED_STDOUT="'../test.txt' -> '${D}/test.txt'
files pushed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes: what is copied"

# everything went to the storage in exactly one commit
COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes: one commit"

# push left nothing behind in the project either
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after push"

# What is really in the storage, read from a fresh clone of it (helper "stored"):
# each of the four files is under ${D}/ at its TARGET and has the content of the local file.
COMMAND='stored "${D}/test.txt"; stored "${D}/xx.ts"; stored "${D}/sub dir/with space.txt"; stored "${D}/home/h.conf"'
EXPECTED_STDOUT="test file
xx config
with space
from home"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored files: plain, from .git, with spaces, from home"

# the config stored itself too, identical to the local one
COMMAND='stored "${D}/gits.sh"'
EXPECTED_STDOUT="$(cat .git/gits.sh)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored config"

# A fresh clone of the storage in ${WORK}/look: the subject of the last commit is "gits push <directory>",
# and next to .git there is only the directory of this project.
COMMAND='storage "${WORK}/look" && git -C "${WORK}/look" log -1 --format=%s && listing "${WORK}/look"'
EXPECTED_STDOUT="gits push ${D}
.git ${D}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "commit message, nothing else in the storage"

# ---------- in sync ----------

# Right after the push: diff says "files are in sync", exit code 0.
# "changed files:" must NOT be printed (asked for, not expected): there is nothing to list.
COMMAND='gits diff 2>&1 | has "files are in sync" "changed files:"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff in sync: no list of changed files"

# isinsync agrees: exit code 0, nothing printed
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync, in sync: prints nothing"

# push without --yes when there is nothing to push: exit code 0 (it was 1 when there was something)
COMMAND='gits push > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push without --yes, in sync"

# push --yes when there is nothing to push: it says so and ends with 0 ...
COMMAND='gits push --yes 2>&1 | has "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes, in sync"

# ... without making an empty commit: still one
COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push --yes, in sync: no new commit"

# ---------- a change ----------

# one of the stored files is edited locally
echo 'changed' > test.txt

# now the local files differ from the storage: 1
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync after a change"

# The diff reads "from the storage to here": "-" is the stored line, "+" the local one.
# "modified:   test.txt": git status is executed in the directory of the project inside the clone,
# so the path has no directory of the project in front.
# "xx config" must NOT be there (not in EXPECTED_STDOUT): files which didn't change are not shown.
COMMAND='gits diff 2>&1 | has "-test file" "+changed" "modified:   test.txt" "xx config"'
EXPECTED_STDOUT="-test file
+changed
modified:   test.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after a change: what is stored, what is here, git status"

# The block of changed files again, exactly: only the edited file, with its absolute local path
# (in a terminal of an editor the path can be clicked), then an empty line and the final url.
COMMAND='gits diff 2>&1 | sed -n "/^changed files:/,/^final url/p"'
EXPECTED_STDOUT="changed files:
  ${WORK}/repo/test.txt

final url ${GITS_SOURCE} (directory ${D})"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after a change: list of changed local files above the final url"

# ---------- a source file which doesn't exist ----------

# One of the listed sources disappears (moved away, to be put back later).
# The local edit of test.txt from the section above is still not pushed.
mv .git/xx.ts "${WORK}/xx.ts"

# diff names the missing file with its absolute path and its verdict is the special
# "at least one source file is missing". Exit code 1.
COMMAND='gits diff 2>&1 | has "source file '"'"'${WORK}/repo/.git/xx.ts'"'"' doesn'"'"'t exist" "files are not in sync - at least one source file is missing"'
EXPECTED_STDOUT="source file '${WORK}/repo/.git/xx.ts' doesn't exist
files are not in sync - at least one source file is missing"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "missing source: diff"

# For isinsync a missing source is "not in sync" (1), not an error (2).
# The error message about the file goes to stderr, thrown away here; stdout stays empty.
COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "missing source: isinsync"

# push with a missing source: everything which exists is stored ("files pushed"), but the exit code
# is 1, so the problem is not silent.
COMMAND='gits push --yes 2>&1 | has "files pushed"'
EXPECTED_STDOUT="files pushed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "push with missing source"

# After that push: a second commit, the edited test.txt arrived in the storage, and xx.ts which
# was missing locally was NOT removed from the storage (it still has the content of the first push).
COMMAND='storage_commits; stored "${D}/test.txt"; stored "${D}/xx.ts"'
EXPECTED_STDOUT="2
changed
xx config"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with missing source: commit, the rest is stored, file of the missing source stays in the storage"

# the missing file is put back
mv "${WORK}/xx.ts" .git/xx.ts

# everything is as stored again: 0
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync again"

# ---------- storage which can't be cloned: error, and the temporary directory is gone ----------

# For this one call the storage points to a directory which doesn't exist. git clone fails:
# gits reports which storage it could not clone, exit code 1.
COMMAND='GITS_SOURCE="${WORK}/nothing-here" gits diff 2>&1 | has "can'"'"'t clone storage GITS_SOURCE=>${WORK}/nothing-here<"'
EXPECTED_STDOUT="can't clone storage GITS_SOURCE=>${WORK}/nothing-here<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "storage not reachable: diff"

# The same with isinsync: exit code 2. It must not answer 1, that would mean "the files differ".
COMMAND='GITS_SOURCE="${WORK}/nothing-here" gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "storage not reachable: isinsync is an error, not 'not in sync'"

# the directory made for the clone was removed also after the failed clone
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after failed clone"

# ---------- targets which could damage the storage are refused ----------

# The good config is remembered, the checks below overwrite .git/gits.sh with broken ones.
CONFIG="$(cat .git/gits.sh)"

# A config whose TARGET is a file directly in the root of the storage ("xx.ts"),
# where it would mix with the directories of all projects.
printf 'GITS_TARGETDIR="%s"\nGITS_LIST=(\n  "xx.ts::xx.ts"\n)\n' "${D}" > .git/gits.sh

# push refuses it with exit code 1 and says where the target should be
F1="target file 'xx.ts' should be in a directory, like 'xxx/xx.ts'"
COMMAND='gits push --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "target in the root of the storage"

# A TARGET which climbs out of the directory of the project with "..": it could overwrite files
# of another project or land outside of the clone.
printf 'GITS_TARGETDIR="%s"\nGITS_LIST=(\n  "xx.ts::$GITS_TARGETDIR/../../xx.ts"\n)\n' "${D}" > .git/gits.sh

# refused, exit code 1
F1="must not contain '..'"
COMMAND='gits push --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "target with .."

# An element which is only a path: neither "::" nor ":e:" in it, so there is no TARGET.
printf 'GITS_TARGETDIR="%s"\nGITS_LIST=(\n  "xx.ts"\n)\n' "${D}" > .git/gits.sh

# refused already by diff (the config is checked when it is read), exit code 1
F1='is neither "SOURCE::TARGET" nor "SOURCE:e:TARGET"'
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "element without separator"

# A config with a list without any element.
printf 'GITS_TARGETDIR="%s"\nGITS_LIST=(\n)\n' "${D}" > .git/gits.sh

# refused: an empty list is taken for a mistake, not for "nothing to do"
F1="shouldn't be empty"
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "empty list"

# A config which doesn't set GITS_TARGETDIR at all.
printf 'GITS_LIST=(\n  "xx.ts::d/xx.ts"\n)\n' > .git/gits.sh

# refused, exit code 1
F1="doesn't define GITS_TARGETDIR"
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no GITS_TARGETDIR"

# the good config is back
echo "${CONFIG}" > .git/gits.sh

# None of the refused configs changed the storage (still the 2 commits from before)
# and none left a temporary clone in the project.
COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was pushed by the refused configs, nothing left behind"
