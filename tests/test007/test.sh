#
# "SOURCE:e:TARGET": stored encrypted. gits doesn't encrypt, it asks the process listening on
# the unix socket GITSTORAGETENCRYPTIONSOCKET - here the real one:
# submodules/encrypt/examples/socket/server.ts with a demo ssh key in a private ssh-agent and --seal,
# the way "socket-002-encoder_process_on_a_socket" of submodules/encrypt/examples/SUMMARY.md shows it.
# The ssenc binary of the submodule (compiled here when it is not there yet) looks at the stored
# files from outside: they have to be ordinary ssenc files which it opens with the same key.
#
# /bin/bash tests/test007/test.sh
# /bin/bash test.sh test007
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

D="git@github.com:tmp__repo.git"

ssenc_build
encoder_start key-one

project repo "git@github.com:tmp/repo.git"
cd repo

printf 'A=1\nB=2\nC=3\n' > .env
echo 'not a secret' > plain.txt
printf 'a "quoted" name\n' > 'we"ird name.txt'

cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"
GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
    "../.env:e:\$GITSTORAGETARGETDIR/.env"
    "../plain.txt::\$GITSTORAGETARGETDIR/plain.txt"
    '../we"ird name.txt:e:'"\$GITSTORAGETARGETDIR/sub dir/we\"ird name.txt"
)
EEE

LISTING='.env .git plain.txt we"ird name.txt'
WEIRD='we"ird name.txt'

# ---------- first diff and push ----------

COMMAND='gits diff 2>&1 | has "+B=2"'
EXPECTED_STDOUT="+B=2"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "first diff: new file in plain text"

F1="'../.env' -> '${D}/.env' (encrypted)"
F2="'../plain.txt' -> '${D}/plain.txt'"

COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}"'
EXPECTED_STDOUT="${F1}
${F2}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push: encrypted element is marked, plain element is not"

COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after push"

COMMAND='stored "${D}/.env" | has "#ssenc1" "#seal" "B=2"'
EXPECTED_STDOUT="#ssenc1
#seal"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env is the output of the encoder, no plain text in it"

COMMAND='stored "${D}/plain.txt"; stored "${D}/sub dir/${WEIRD}" | has "#ssenc1"'
EXPECTED_STDOUT="not a secret
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored plain.txt is plain, file with a quote and a space in the name is encrypted"

# seen from outside: the ssenc binary of submodules/encrypt opens what gits stored, with the same key
COMMAND='ssenc decrypt --ssh-key "${WORK}/keys/key-one.pub" -i "${WORK}/look/${D}/.env"'
EXPECTED_STDOUT="A=1
B=2
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env is an ordinary ssenc file: the ssenc binary decrypts it"

COMMAND='ssenc inspect -i "${WORK}/look/${D}/.env" | has "\"format\":\"ssenc1\"" "\"mode\":\"lines\"" "\"seal\":true" "\"type\":\"ssh\""'
EXPECTED_STDOUT='"format":"ssenc1"
"mode":"lines"
"seal":true
"type":"ssh"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env: line by line, sealed, opened by an ssh key"

# the plain copy made for the moment of encryption (TARGET.hash...) never reaches the storage
COMMAND='storage "${WORK}/look" && cd "${WORK}/look" && git ls-files | has "hash"; git ls-files | wc -l | tr -d " "'
EXPECTED_STDOUT="4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "four files in the storage, no temporary files"

stored "${D}/.env" > "${WORK}/v1"

# ---------- in sync ----------

COMMAND='gits diff 2>&1 | has "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff in sync"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync in sync"

COMMAND='gits push --yes > /dev/null 2>&1; storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push of unchanged files: no commit"

# ---------- one line edited: the diff is in plain text ----------

printf 'A=1\nB=22\nC=3\n' > .env

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync after an edit"

F1="-B=2
+B=22"

# nothing encrypted is shown, the other files are not there
COMMAND='gits diff 2>&1 | has "${F1}" "#ssenc1" "plain.txt"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after an edit is in plain text"

# the commit with decrypted files stays in the temporary clone
COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff doesn't push"

COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; storage_commits'
EXPECTED_STDOUT="0
2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second push: commit"

stored "${D}/.env" > "${WORK}/v2"

# the existing stored file is the "previous version" for the encoder: only the edited line differs,
# and the #seal line (--seal: one line which covers the whole file) - 2 lines, each as "<" and as ">"
COMMAND='{ diff "${WORK}/v1" "${WORK}/v2" || true; } | grep -c "^[<>]"; { diff "${WORK}/v1" "${WORK}/v2" || true; } | grep -c "^[<>] #seal"; git -C "${WORK}/look" show --stat --format= HEAD | grep -c "|"'
EXPECTED_STDOUT="4
2
1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "only the edited line changed in the stored file, only .env is in the second commit"

COMMAND='ssenc decrypt --ssh-key "${WORK}/keys/key-one.pub" -i "${WORK}/v2"'
EXPECTED_STDOUT="A=1
B=22
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second push: the ssenc binary decrypts the new version"

# ---------- pull decrypts ----------

rm .env "${WEIRD}"

COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat .env "${WEIRD}"; listing'
EXPECTED_STDOUT="0
A=1
B=22
C=3
a \"quoted\" name
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull: files are plain, also the one with a quote in the name"

# ---------- state decrypts too ----------

COMMAND='cd "${WORK}" && gits state 2>&1 | has "COUNT_SUCCESS : 1"'
EXPECTED_STDOUT="COUNT_SUCCESS : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: in sync"

printf 'A=1\nB=22\nC=33\n' > .env

COMMAND='cd "${WORK}" && gits state 2>&1 | has "modified:   ${D}/.env"'
EXPECTED_STDOUT="modified:   ${D}/.env"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state after an edit"

printf 'A=1\nB=22\nC=3\n' > .env

# ---------- no socket defined: explained, nothing happens ----------

unset GITSTORAGETENCRYPTIONSOCKET

for CMD in diff "push --yes" "pull --yes"; do
  COMMAND="gits ${CMD} 2>&1 | has 'env var GITSTORAGETENCRYPTIONSOCKET is not defined'"
  EXPECTED_STDOUT="env var GITSTORAGETENCRYPTIONSOCKET is not defined"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "${CMD} without socket"
done

COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "isinsync without socket is an error"

# ---------- nobody listens ----------

export GITSTORAGETENCRYPTIONSOCKET="${WORK}/nobody.sock"

F1="can't connect to the encoder process on socket GITSTORAGETENCRYPTIONSOCKET=>${WORK}/nobody.sock<"

COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "socket nobody listens on"

COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was pushed without the encoder, nothing left behind"

# ---------- the encoder has another key: nothing is decrypted, nothing is overwritten, nothing is pushed ----------

encoder_start key-two
printf 'local edit\n' > .env

F1="can't decrypt '${D}/.env': AUTH"

COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, diff"

COMMAND='gits pull --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, pull"

COMMAND='cat .env'
EXPECTED_STDOUT="local edit"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrong key, pull: local file untouched"

COMMAND='gits push --yes > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, push"

COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrong key, push: nothing pushed, nothing left behind"

printf 'A=1\nB=22\nC=3\n' > .env

encoder_start key-one

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync again with the right key"

# ---------- an element changed from "::" to ":e:": stored plain until the next push ----------

sed -i.bak 's|"../plain.txt::|"../plain.txt:e:|' .git/gits.sh && rm .git/gits.sh.bak

F1="'${D}/plain.txt' is marked :e: but it is stored not encrypted"

# exit code 1: the config changed
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "plain -> encrypted, diff: note"

COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/plain.txt" | has "#ssenc1" "not a secret"'
EXPECTED_STDOUT="0
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "plain -> encrypted, push: stored encrypted now"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "plain -> encrypted: in sync after push"

# ---------- and back ----------

sed -i.bak 's|"../plain.txt:e:|"../plain.txt::|' .git/gits.sh && rm .git/gits.sh.bak

COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/plain.txt"'
EXPECTED_STDOUT="0
not a secret"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted -> plain: stored plain again"

COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted -> plain: in sync after push"

# ---------- the config itself can be encrypted, init on another machine restores it decrypted ----------

sed -i.bak 's|"gits.sh::|"gits.sh:e:|' .git/gits.sh && rm .git/gits.sh.bak

COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/gits.sh" | has "#ssenc1" "GITSTORAGELIST"'
EXPECTED_STDOUT="0
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted config in the storage"

cd ..
project two "git@github.com:tmp/repo.git"
cd two

COMMAND='GITSTORAGETENCRYPTIONSOCKET="" gits init 2>&1 | has "is encrypted, define env var GITSTORAGETENCRYPTIONSOCKET"'
EXPECTED_STDOUT="is encrypted, define env var GITSTORAGETENCRYPTIONSOCKET"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, encrypted config, no socket"

COMMAND='listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init, encrypted config, no socket: nothing created"

COMMAND='gits init > /dev/null 2>&1; echo "${?}"; diff .git/gits.sh ../repo/.git/gits.sh'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init, encrypted config: restored decrypted"

COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat .env'
EXPECTED_STDOUT="0
A=1
B=22
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull on the other machine"
