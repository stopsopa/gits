#
# The config is a shell script (GITSTORAGETESHELL), init with a template (GITSTORAGETEMPLATE), url, move.
#
# /bin/bash tests/test008/test.sh
# /bin/bash test.sh test008
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

source "${_DIR}/../_lib.sh"

D="git@github.com:tmp__repo.git"

# ---------- init: where it can't work ----------

mkdir notrepo

COMMAND='cd notrepo && gits init 2>&1 | has "you have to execute it in the directory where .git exists"'
EXPECTED_STDOUT="you have to execute it in the directory where .git exists"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init outside of a repository"

mkdir noremote
git -C noremote init -q .

F1="has no remote 'origin'"

COMMAND='cd noremote && gits init 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init without remote origin"

COMMAND='listing noremote'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init without remote origin: nothing created"

# ---------- init with a template ----------

project repo "git@github.com:tmp/repo.git"
cd repo

cat <<'EEE' > "${WORK}/template.sh"
# my template
  GITSTORAGETARGETDIR="will be replaced"
GITSTORAGELIST=(
    "gits.sh::$GITSTORAGETARGETDIR/gits.sh"
    "../from-template.txt::$GITSTORAGETARGETDIR/from-template.txt"
)
EEE

COMMAND='GITSTORAGETEMPLATE="${WORK}/missing.sh" gits init 2>&1 | has "template GITSTORAGETEMPLATE=>${WORK}/missing.sh<"'
EXPECTED_STDOUT="template GITSTORAGETEMPLATE=>${WORK}/missing.sh<"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, template which doesn't exist"

echo "no variable here" > "${WORK}/bad-template.sh"

COMMAND='GITSTORAGETEMPLATE="${WORK}/bad-template.sh" gits init 2>&1 | has "there is no line starting with GITSTORAGETARGETDIR= in the template"'
EXPECTED_STDOUT="there is no line starting with GITSTORAGETARGETDIR= in the template"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, template without GITSTORAGETARGETDIR"

COMMAND='listing; listing .git | has "gits.sh"'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "failed init creates nothing, no config"

COMMAND='GITSTORAGETEMPLATE="${WORK}/template.sh" gits init 2>&1 | has "generated (template ${WORK}/template.sh)"'
EXPECTED_STDOUT="generated (template ${WORK}/template.sh)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init with a template"

COMMAND='cat .git/gits.sh'
EXPECTED_STDOUT="# my template
  GITSTORAGETARGETDIR=\"${D}\"
GITSTORAGELIST=(
    \"gits.sh::\$GITSTORAGETARGETDIR/gits.sh\"
    \"../from-template.txt::\$GITSTORAGETARGETDIR/from-template.txt\"
)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "config made from the template: only GITSTORAGETARGETDIR is changed"

# ~/ in the path of the template
rm .git/gits.sh
cp "${WORK}/template.sh" "${HOME}/t.sh"

F1="GITSTORAGETARGETDIR=\"${D}\""

COMMAND='GITSTORAGETEMPLATE="~/t.sh" gits init > /dev/null 2>&1; echo "${?}"; cat .git/gits.sh | has "${F1}"'
EXPECTED_STDOUT="0
${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init with a template in home"

# ---------- url ----------

COMMAND='gits url 2>&1; listing'
EXPECTED_STDOUT="final url ${GITSTORAGESOURCE} (directory ${D})
.git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "url of a storage which is a directory, url creates nothing"

# ---------- move ----------

F1="from: git@xxx:project__source-repo.git"
F2="to:   git@yyy:other__target-repo.git"
F3="git clone \"${GITSTORAGESOURCE}\" ."
F4='git mv "git@xxx:project__source-repo.git" "git@yyy:other__target-repo.git"'
F5='git remote set-url origin "git@yyy:other/target-repo.git"'
F6='GITSTORAGETARGETDIR="git@yyy:other__target-repo.git"'

COMMAND='gits move git@xxx:project/source-repo.git git@yyy:other/target-repo.git 2>&1 | has "${F1}" "${F2}" "${F3}" "${F4}" "${F5}" "${F6}"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}
${F4}
${F5}
${F6}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "move: old directory, new directory, clone of the storage, rename, remote, config"

COMMAND='storage_commits; listing'
EXPECTED_STDOUT="0
.git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "move changes nothing and creates nothing"

COMMAND='gits move only-one 2>&1 | has "usage: gits move <old remote> <new remote>"'
EXPECTED_STDOUT="usage: gits move <old remote> <new remote>"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "move with one argument"

# ---------- the config is executed: from the root of the project, by the shell from GITSTORAGETESHELL ----------

echo "one" > one.txt
echo "two" > two.txt
cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"

echo "config says: pwd is \$(pwd)"
echo "config warns on stderr" >&2

GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
)

# elements computed while the config runs
for NAME in one two three; do
  if [ -f "\${NAME}.txt" ]; then
    GITSTORAGELIST+=("../\${NAME}.txt::\$GITSTORAGETARGETDIR/computed/\${NAME}.txt")
  fi
done
EEE

F1="config says: pwd is ${WORK}/repo"
F2="config warns on stderr"
F3="'../two.txt' -> '${D}/computed/two.txt'"

# three.txt: element which was not added by the config
COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}" "${F3}" "three.txt"'
EXPECTED_STDOUT="${F1}
${F2}
${F3}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "computed config, push: executed from the root of the project, its stdout and stderr are shown, computed element"

COMMAND='storage "${WORK}/look" && listing "${WORK}/look/${D}/computed"'
EXPECTED_STDOUT="one.txt two.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored computed elements"

COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "computed config, isinsync: stdout of the config is not shown"

# another shell: a wrapper which leaves a trace and passes everything to bash
cat <<EEE > "${WORK}/myshell"
#!/bin/bash
echo "called" >> "${WORK}/myshell.log"
exec /bin/bash "\${@}"
EEE
chmod +x "${WORK}/myshell"

COMMAND='GITSTORAGETESHELL="${WORK}/myshell" gits isinsync 2> /dev/null; echo "${?}"; cat "${WORK}/myshell.log"'
EXPECTED_STDOUT="0
called"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the config was executed by the shell from GITSTORAGETESHELL"

# default is /bin/bash, also when the variable is empty
COMMAND='GITSTORAGETESHELL="" gits isinsync 2> /dev/null; echo "${?}"; cat "${WORK}/myshell.log"'
EXPECTED_STDOUT="0
called"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "empty GITSTORAGETESHELL: default is used, the wrapper was not called again"

F1="can't run shell GITSTORAGETESHELL=>${WORK}/no-such-shell<"

COMMAND='GITSTORAGETESHELL="${WORK}/no-such-shell" gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "shell which doesn't exist"

if command -v zsh > /dev/null 2>&1; then
  COMMAND='ZDOTDIR="${HOME}" GITSTORAGETESHELL="$(command -v zsh)" gits diff 2>&1 | has "files are in sync"'
  EXPECTED_STDOUT="files are in sync"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "config executed by zsh"
fi

# a config which ends the shell can't be read
echo 'exit 0' >> .git/gits.sh

COMMAND='gits diff 2>&1 | has "didn'"'"'t run to its end"'
EXPECTED_STDOUT="didn't run to its end"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "config which calls exit"

COMMAND='listing'
EXPECTED_STDOUT=".git one.txt two.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing left behind at the end"
