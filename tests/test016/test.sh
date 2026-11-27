#
# Encryption of the storage as a whole, through the demo examples/encrypt (ENCRYPT_PROCESS.md):
# its wrapper gits.sh starts an encoder process for every command (start.sh, at the event START)
# and stops it at the end (stop.sh, GITS_EXIT), its reset_setup.sh creates a storage and two
# projects. Everything is created in tests/test016/tmp/demo (GITS_DEMO_WORK), not in examples/encrypt.
#
# What is tested, in this order:
#
#   scenario A: plain -> encrypted -> everything decrypted -> encrypted with another key
#     1. reset_setup.sh: storage, repoa, repob, two keys; nothing is stored yet
#     2. no GITS_ENCRYPTION_SOCKET: ':e:' is ignored, push stores the files as they are
#     3. with the socket: a ':e:' file stored plain is used as it is (in sync), push encrypts it,
#        "gits crypt encrypt" encrypts what is still plain (text: lines mode, binary: blob mode)
#     4. no socket + stored encrypted: an error for diff, push, pull (isinsync: exit code 2)
#     5. gits crypt decrypt --storage --yes: the whole storage is plain again, and gits works
#        without the socket again
#     6. gits crypt encrypt all --yes with the second key: every file has that key, the first
#        key doesn't open them (AUTH)
#
#   scenario B (after reset_setup.sh again): encrypted -> rekey
#     7. push with the first key
#     8. gits crypt rekey: refused by a server without new keys; without --yes only a list;
#        with --yes every file has the second key, the first is out
#     9. gits crypt rekey --rewrap-only: only the key line changes, the content stays byte for byte
#    10. after every command nothing runs and no socket is left; wrong arguments are explained
#
# Needs: the compiled binary (/bin/bash compile.sh), Node.js >= 22.18, ssh-keygen / ssh-agent /
# ssh-add, esbuild (pnpm install), the ssenc binary of the encrypt repository (encrypt.sh copies it).
#
# /bin/bash tests/test016/test.sh
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



ENC="${_ROOT}/examples/encrypt"
DEMO="${WORK}/demo"

# the demo creates everything here, and its wrapper starts the binary under test
export GITS_DEMO_WORK="${DEMO}"
export GITS_DEMO_BIN="${BIN}"

# the storage of the demo, seen from the test
SRC="${DEMO}/gits_source"
A="git@github.com:demo__repoa.git"
B="git@github.com:demo__repob.git"

# gits through the wrapper of the demo: encoder process started and stopped around the command
function w {
  /bin/bash "${ENC}/gits.sh" "${@}"
}

# the same wrapper, but gits gets no GITS_ENCRYPTION_SOCKET and nothing is started
function plain {
  GITS_ENCRYPTION_SOCKET= w "${@}"
}

# form <file in the storage>: how it is stored
function form {
  case "$(head -c 13 "${SRC}/${1}")" in
    "#ssenc1 lines") echo "encrypted lines" ;;
    "#ssenc1 blob "*) echo "encrypted blob" ;;
    *) echo "plain" ;;
  esac
}

function forms {
  echo "$(form "${A}/.env") | $(form "${B}/.env.local") | $(form "${B}/secrets/token.txt") | $(form "${B}/secrets/cert.bin")"
}

function commits {
  git -C "${SRC}" rev-list --count --all 2> /dev/null || echo 0
}

# fingerprint of a key of the demo: fp key | fp key2
function fp {
  ssh-keygen -lf "${DEMO}/tmp/${1}.pub" | cut -d " " -f 2
}

# how many files of the storage are opened by the key: with <fingerprint>
function with {
  w crypt status --storage 2>&1 | grep -c -F "[${1}]"
}

# ======================= scenario A =======================

# ---------- 1. state 0 ----------

COMMAND='/bin/bash "${ENC}/reset_setup.sh" 2>&1 | has "state 0 is ready"; listing "${DEMO}"; listing "${DEMO}/tmp"; commits'
EXPECTED_STDOUT="state 0 is ready
gits_source repoa repob server.log tmp
key key.pub key2 key2.pub
0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "reset_setup.sh: storage, two projects, two keys, nothing stored"

# registered by reset_setup.sh with "gits add -e": one in repoa, three in repob (one of them binary)
COMMAND='cd "${DEMO}" && w crypt status all 2>&1 | has "missing    ${A}/.env" "missing    ${B}/secrets/cert.bin" "encrypted: 0, plain: 0, not stored yet: 4"'
EXPECTED_STDOUT="missing    ${A}/.env
missing    ${B}/secrets/cert.bin
encrypted: 0, plain: 0, not stored yet: 4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt status all: four :e: files, not stored yet"

# ---------- 2. no socket: ':e:' is ignored ----------

cd "${DEMO}/repoa"

COMMAND='plain push --yes 2>&1 | has "GITS_ENCRYPTION_SOCKET is not defined: '"'"':e:'"'"' is ignored" "(encrypted)" "files pushed"; form "${A}/.env"; cmp .env "${SRC}/${A}/.env" && echo identical'
EXPECTED_STDOUT="GITS_ENCRYPTION_SOCKET is not defined: ':e:' is ignored
files pushed
plain
identical"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no socket: push stores the :e: file as it is"

COMMAND='plain isinsync; echo "code ${?}"'
EXPECTED_STDOUT="code 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no socket: isinsync 0"

# ---------- 3. with the socket ----------

# stored plain, marked :e:: used as it is, said, and still in sync (the content is the same)
COMMAND='w diff 2>&1 | has "is marked :e: but it is stored not encrypted" "files are in sync"'
EXPECTED_STDOUT="is marked :e: but it is stored not encrypted
files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "socket + stored plain: used as it is"

# without --yes: only what would change
COMMAND='w crypt encrypt 2>&1 | has "would change in the storage" "  ${A}/.env" "gits crypt encrypt --yes"; form "${A}/.env"'
EXPECTED_STDOUT="would change in the storage
  ${A}/.env
gits crypt encrypt --yes
plain"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt encrypt without --yes: a list, nothing changed"

COMMAND='w crypt encrypt > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "crypt encrypt without --yes: exit code 1"

cd "${DEMO}/repob"

# push with the socket encrypts: text in lines mode, the binary file in blob mode (decided by the library)
COMMAND='w push --yes 2>&1 | has "files pushed"; forms'
EXPECTED_STDOUT="files pushed
plain | encrypted lines | encrypted lines | encrypted blob"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the socket: repob stored encrypted, repoa still plain"

cd "${DEMO}/repoa"

# only the storage is changed, the local file stays
COMMAND='w crypt encrypt --yes 2>&1 | has "encrypt: '"'"'${A}/.env'"'"'" "1 files changed in the storage"; forms; head -n 1 .env'
EXPECTED_STDOUT="encrypt: '${A}/.env'
1 files changed in the storage
encrypted lines | encrypted lines | encrypted lines | encrypted blob
API_KEY=repoa-abc123"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt encrypt --yes: the plain one is encrypted in the storage"

COMMAND='w crypt encrypt --yes 2>&1 | has "nothing to do"; w isinsync; echo "repoa ${?}"; cd "${DEMO}/repob" && w isinsync; echo "repob ${?}"'
EXPECTED_STDOUT="nothing to do
repoa 0
repob 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "again: nothing to do, both projects in sync"

COMMAND='cd "${DEMO}" && w crypt status all 2>&1 | has "encrypted: 4, plain: 0, not stored yet: 0"; with "$(fp key)"'
EXPECTED_STDOUT="encrypted: 4, plain: 0, not stored yet: 0
4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt status: four encrypted, all with the first key"

# ---------- 4. no socket + stored encrypted ----------

for CMD in diff "push --yes" "pull --yes"; do
  COMMAND="plain ${CMD} 2>&1 | has 'is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined'; head -n 1 .env; form '${A}/.env'"
  EXPECTED_STDOUT="is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined
API_KEY=repoa-abc123
encrypted lines"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "no socket + stored encrypted: ${CMD} refuses, nothing touched"
done

COMMAND='plain isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "no socket + stored encrypted: isinsync 2"

# ---------- 5. decrypt the whole storage ----------

COMMITS="$(commits)"

COMMAND='cd "${DEMO}" && plain crypt decrypt --storage --yes 2>&1 | has "needs the encoder process"; forms'
EXPECTED_STDOUT="needs the encoder process
encrypted lines | encrypted lines | encrypted lines | encrypted blob"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt decrypt without the socket: explained"

COMMAND='cd "${DEMO}" && w crypt decrypt --storage --yes 2>&1 | has "4 files changed in the storage"; forms; echo "$(( $(commits) - COMMITS )) commit"; cmp repoa/.env "${SRC}/${A}/.env" && cmp repob/secrets/cert.bin "${SRC}/${B}/secrets/cert.bin" && echo identical'
EXPECTED_STDOUT="4 files changed in the storage
plain | plain | plain | plain
1 commit
identical"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt decrypt --storage --yes: everything plain, one commit"

COMMAND='plain isinsync; echo "repoa ${?}"; cd "${DEMO}/repob" && plain isinsync; echo "repob ${?}"; cd "${DEMO}" && w crypt status --storage 2>&1 | has "encrypted: 0"'
EXPECTED_STDOUT="repoa 0
repob 0
encrypted: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after it gits works without the socket"

# ---------- 6. encrypt everything with another key ----------

export GITS_DEMO_SSH_KEY="key2"

COMMAND='cd "${DEMO}" && w crypt encrypt all --yes 2>&1 | has "4 files changed in the storage"; forms; with "$(fp key2)"; with "$(fp key)"'
EXPECTED_STDOUT="4 files changed in the storage
encrypted lines | encrypted lines | encrypted lines | encrypted blob
4
0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "crypt encrypt all --yes with key2: every file has key2"

COMMAND='w isinsync; echo "repoa ${?}"; cd "${DEMO}/repob" && w isinsync; echo "repob ${?}"'
EXPECTED_STDOUT="repoa 0
repob 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "key2 opens them: in sync"

unset GITS_DEMO_SSH_KEY

COMMAND='w diff 2>&1 | has "AUTH" "is it stored with another key"'
EXPECTED_STDOUT="AUTH
is it stored with another key"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "the first key doesn't open them"

# ======================= scenario B =======================

# ---------- 7. from scratch, stored encrypted with the first key ----------

COMMAND='/bin/bash "${ENC}/reset_setup.sh" > /dev/null 2>&1; echo "reset ${?}"; commits; cd "${DEMO}/repoa" && w push --yes 2>&1 | has "files pushed"; cd "${DEMO}/repob" && w push --yes 2>&1 | has "files pushed"; forms; with "$(fp key)"'
EXPECTED_STDOUT="reset 0
0
files pushed
files pushed
encrypted lines | encrypted lines | encrypted lines | encrypted blob
4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "reset, push both projects: four files with the first key"

# ---------- 8. rekey ----------

cd "${DEMO}"
COMMITS="$(commits)"

# the server has only the key which opens the files: it can't know the new one
COMMAND='w crypt rekey --storage --yes 2>&1 | has "USAGE" "started without GITS_DEMO_NEW_SSH_KEY" "Nothing was changed in the storage"; echo "$(( $(commits) - COMMITS )) commit"'
EXPECTED_STDOUT="USAGE
started without GITS_DEMO_NEW_SSH_KEY
Nothing was changed in the storage
0 commit"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey: refused by a server without new keys"

export GITS_DEMO_NEW_SSH_KEY="key2"

COMMAND='w crypt rekey --storage 2>&1 | has "would change in the storage" "  ${B}/secrets/cert.bin" "gits crypt rekey --storage --yes"; echo "$(( $(commits) - COMMITS )) commit"'
EXPECTED_STDOUT="would change in the storage
  ${B}/secrets/cert.bin
gits crypt rekey --storage --yes
0 commit"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey --storage without --yes: a list"

COMMAND='w crypt rekey --storage --yes 2>&1 | has "4 files changed in the storage"; echo "$(( $(commits) - COMMITS )) commit"; forms'
EXPECTED_STDOUT="4 files changed in the storage
1 commit
encrypted lines | encrypted lines | encrypted lines | encrypted blob"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey --storage --yes: one commit"

unset GITS_DEMO_NEW_SSH_KEY

COMMAND='with "$(fp key2)"; with "$(fp key)"'
EXPECTED_STDOUT="4
0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "every file has key2, the first key is out"

cd "${DEMO}/repoa"

COMMAND='w diff 2>&1 | has "AUTH"'
EXPECTED_STDOUT="AUTH"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "after rekey: the first key doesn't open"

export GITS_DEMO_SSH_KEY="key2"

# the content survived the rekey: pull brings back a removed local file, also the binary one
COMMAND='w isinsync; echo "repoa ${?}"; cd "${DEMO}/repob" && cp secrets/cert.bin "${WORK}/cert.before" && rm secrets/cert.bin .env.local && w pull --yes 2>&1 | has "files pulled"; cmp secrets/cert.bin "${WORK}/cert.before" && cat .env.local'
EXPECTED_STDOUT="repoa 0
files pulled
STRIPE_KEY=repob-sk_test_123"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after rekey: key2 opens, pull brings the same content"

# ---------- 9. rewrap: only the key line ----------

cp "${SRC}/${A}/.env" "${WORK}/env.before"
export GITS_DEMO_NEW_SSH_KEY="key"

# this project only (its one :e: file). Line 2 is the key line, the rest is the content
COMMAND='w crypt rekey --rewrap-only --yes 2>&1 | has "rekey --rewrap-only: '"'"'${A}/.env'"'"'" "1 files changed in the storage"; diff "${WORK}/env.before" "${SRC}/${A}/.env" | grep -c "^[<>]"; diff <(sed 2d "${WORK}/env.before") <(sed 2d "${SRC}/${A}/.env") && echo "content identical"'
EXPECTED_STDOUT="rekey --rewrap-only: '${A}/.env'
1 files changed in the storage
2
content identical"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey --rewrap-only: only the key line changed"

unset GITS_DEMO_NEW_SSH_KEY
unset GITS_DEMO_SSH_KEY

# repoa is back on the first key, repob stays on key2
COMMAND='w isinsync; echo "repoa ${?}"; cd "${DEMO}" && with "$(fp key)"; with "$(fp key2)"'
EXPECTED_STDOUT="repoa 0
1
3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after rewrap: the first key opens repoa again"

# ---------- 10. nothing left, wrong arguments ----------

COMMAND='listing "${DEMO}/tmp"'
EXPECTED_STDOUT="key key.pub key2 key2.pub"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no socket, no pid file left by any command"

COMMAND='w crypt 2>&1 | has "usage: gits crypt status|encrypt|decrypt|rekey"'
EXPECTED_STDOUT="usage: gits crypt status|encrypt|decrypt|rekey"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "crypt without a verb: usage"

COMMAND='w crypt encrypt --storage --yes 2>&1 | has "only a config" "gits crypt encrypt all"'
EXPECTED_STDOUT="only a config
gits crypt encrypt all"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "crypt encrypt --storage: explained"

COMMAND='w crypt decrypt --rewrap-only 2>&1 | has "--rewrap-only is only for: gits crypt rekey"'
EXPECTED_STDOUT="--rewrap-only is only for: gits crypt rekey"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "--rewrap-only with another verb: explained"

/bin/bash "${ENC}/stop.sh"
