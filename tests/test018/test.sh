#
# The demo examples/encrypt_os_ssh_agent (its ENCRYPT_PROCESS.md): the same as tests/test016 does
# for examples/encrypt, but here the demo starts NO ssh-agent of its own. Its start.sh uses the
# agent of the terminal (SSH_AUTH_SOCK) and only checks that the key is loaded in it.
#
# "The agent of the terminal" is, in this test, a private agent the test starts itself
# (${WORK}/agent.sock, agent_start of tests/_lib.sh) and exports as SSH_AUTH_SOCK: the agent
# of the developer is never asked and never changed. Everything else is created in
# tests/test018/tmp/demo (GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES), not in examples/encrypt_os_ssh_agent.
#
# What is tested, in this order:
#
#   scenario A: plain -> encrypted -> everything decrypted -> encrypted with another key
#     1. reset_setup.sh: storage, repoa, repob, two keys in keys/; nothing is stored yet. It works
#        with keys which are not loaded. A command which needs the key stops with what ssenc
#        said (not loaded; no SSH_AUTH_SOCK). Then the test loads both keys (ssh-add)
#     2. no GITS_ENCRYPTION_SOCKET: ':e:' is ignored, push stores the files as they are
#     3. with the socket: a ':e:' file stored plain is used as it is (in sync), push encrypts it,
#        "gits crypt encrypt" encrypts what is still plain (text: lines mode, binary: blob mode)
#     4. no socket + stored encrypted: an error for diff, push, pull (isinsync: exit code 2)
#     5. gits crypt decrypt --storage --yes: the whole storage is plain again
#     6. gits crypt encrypt all --yes with the second key: every
#        file has that key, the first key doesn't open them (AUTH)
#
#   scenario B (after reset_setup.sh again: it takes every key with "gits" in its label out
#   of the agent, the key files stay; the test loads the two of the demo again):
#     7. push with the first key
#     8. gits crypt rekey: refused by a server
#        without a new key; without --yes only a list; with --yes every file has the second key
#     9. gits crypt rekey --rewrap-only: only the key line changes
#    10. after every command no server runs and no socket is left, the agent still has both
#        keys (stop.sh doesn't touch it); wrong arguments are explained
#
# Needs: the compiled binary (/bin/bash compile.sh), Node.js >= 22.18, ssh-keygen / ssh-agent /
# ssh-add, esbuild (pnpm install), the ssenc binary of the encrypt repository (encrypt.sh copies it).
#
# /bin/bash tests/test018/test.sh
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



ENC="${_ROOT}/examples/encrypt_os_ssh_agent"
DEMO="${WORK}/demo"

# "the agent of the terminal": a private one of this test, see the comment at the top.
# agent_start stops the test when that agent doesn't answer, so nothing below can reach another one
agent_start
export SSH_AUTH_SOCK="${AGENT_SOCK}"

# the demo creates everything here, and its wrapper starts the binary under test
export GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES="${DEMO}"
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
  ssh-keygen -lf "${DEMO}/keys/${1}.pub" | cut -d " " -f 2
}

# how many files of the storage are opened by the key: with <fingerprint>
function with {
  w crypt status --storage 2>&1 | grep -c -F "[${1}]"
}

# ======================= scenario A =======================

# ---------- 1. state 0 ----------

# the keys are not loaded yet: reset_setup.sh works anyway (init and add encrypt nothing) and says what to load
COMMAND='/bin/bash "${ENC}/reset_setup.sh" 2>&1 | has "state 0 is ready" "not loaded in the ssh-agent of this terminal" "ssh-add \"${DEMO}/keys/key\" \"${DEMO}/keys/key2\""; listing "${DEMO}"; listing "${DEMO}/keys"; commits; ssh-add -l'
EXPECTED_STDOUT="state 0 is ready
not loaded in the ssh-agent of this terminal
ssh-add \"${DEMO}/keys/key\" \"${DEMO}/keys/key2\"
gits_source keys repoa repob
key key.pub key2 key2.pub
0
The agent has no identities."
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "reset_setup.sh: storage, two projects, two keys which nobody loaded, nothing stored"

# a command which encrypts, with the key not loaded: the test of start.sh fails with what ssenc
# said, and gits stops before anything is done
COMMAND='cd "${DEMO}/repoa" && w push --yes 2>&1 | has "error ENV key $(fp key) is not loaded in ssh-agent (check: ssh-add -l)" "is not the key of the demo" "GITS_START" "files pushed"; commits; listing "${DEMO}/tmp"'
EXPECTED_STDOUT="error ENV key $(fp key) is not loaded in ssh-agent (check: ssh-add -l)
GITS_START
0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "key not loaded: gits stops before doing anything, nothing is left running"

COMMAND='cd "${DEMO}/repoa" && SSH_AUTH_SOCK= w diff 2>&1 | has "ssh-agent not available: SSH_AUTH_SOCK is not set"'
EXPECTED_STDOUT="ssh-agent not available: SSH_AUTH_SOCK is not set"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no SSH_AUTH_SOCK: explained"

COMMAND='cd "${DEMO}/repoa" && GITS_ENCRYPTION_SSH_KEY="SHA256:nosuchkey" w diff 2>&1 | has "key SHA256:nosuchkey is not loaded in ssh-agent" "the key which was asked for is not the key of the demo" "GITS_ENCRYPTION_SSH_KEY=>SHA256:nosuchkey<" "unset GITS_ENCRYPTION_SSH_KEY"'
EXPECTED_STDOUT="key SHA256:nosuchkey is not loaded in ssh-agent
the key which was asked for is not the key of the demo
GITS_ENCRYPTION_SSH_KEY=>SHA256:nosuchkey<
unset GITS_ENCRYPTION_SSH_KEY"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "a fingerprint of no key: explained"

# the default of env.sh is the fingerprint read from keys/key.pub. No such file: empty, and said
COMMAND='mv "${DEMO}/keys/key.pub" "${WORK}/key.pub.away"; cd "${DEMO}/repoa" && w diff 2>&1 | has "env var GITS_ENCRYPTION_SSH_KEY is not defined"; mv "${WORK}/key.pub.away" "${DEMO}/keys/key.pub"'
EXPECTED_STDOUT="env var GITS_ENCRYPTION_SSH_KEY is not defined"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no public key file to read the default from: explained"

# what the guide tells the user to do by hand. Only into the agent of this test
function load_keys {
  if [[ "${SSH_AUTH_SOCK}" != "${WORK}/agent.sock" ]]; then
    fail "SSH_AUTH_SOCK=>${SSH_AUTH_SOCK}< is not the agent of this test, no key is loaded"
  fi
  ssh-add -q "${DEMO}/keys/key" "${DEMO}/keys/key2" || fail "ssh-add failed"
}

load_keys

COMMAND='/bin/bash "${ENC}/keys.sh" | has "both keys are loaded"; ssh-add -l | grep -c "gits-os-agent-demo"'
EXPECTED_STDOUT="both keys are loaded
2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after ssh-add: keys.sh sees both keys in the agent"

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

# stdin of a test is not a terminal: the warning with the list of the files, nobody is asked
COMMAND='plain push --yes 2>&1 | has "GITS_ENCRYPTION_SOCKET is not defined: '"'"':e:'"'"' is ignored" "WITHOUT ENCRYPTION, although marked '"'"':e:'"'"':" "    '"'"'../.env'"'"'" "Enter: go on" "(encrypted)" "files pushed"; form "${A}/.env"; cmp .env "${SRC}/${A}/.env" && echo identical'
EXPECTED_STDOUT="GITS_ENCRYPTION_SOCKET is not defined: ':e:' is ignored
WITHOUT ENCRYPTION, although marked ':e:':
    '../.env'
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

# the binary itself, with a socket nobody listens on (the wrapper would start a server there)
function dead {
  GITS_SOURCE="${SRC}" GITS_ENCRYPTION_SOCKET="${WORK}/nobody.sock" "${BIN}" "${@}"
}

# a socket which doesn't work is like no socket: the reason is said, the command goes on
COMMAND='dead pull --yes 2>&1 | has "can'"'"'t connect to the encoder process on socket GITS_ENCRYPTION_SOCKET=>${WORK}/nobody.sock<" "'"'"':e:'"'"' is ignored" "WITHOUT ENCRYPTION, although marked '"'"':e:'"'"':"; dead isinsync; echo "code ${?}"'
EXPECTED_STDOUT="can't connect to the encoder process on socket GITS_ENCRYPTION_SOCKET=>${WORK}/nobody.sock<
':e:' is ignored
WITHOUT ENCRYPTION, although marked ':e:':
code 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "socket nobody listens on: like no socket, with the reason"

# a config without any ':e:': nothing about encryption is said, with no socket and with a dead one.
# (the config itself is a stored file: pull brings the stored one back, nothing is pushed here)
cp .git/gits.sh "${WORK}/gits.sh.backup"
sed -i.bak 's/:e:/::/' .git/gits.sh && rm .git/gits.sh.bak
COMMAND='(plain diff; dead diff; dead pull --yes) 2>&1 | grep -c "is ignored\|WITHOUT ENCRYPTION\|encoder process"'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no ':e:' in the config: no warning at all"
cp "${WORK}/gits.sh.backup" .git/gits.sh

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

# the second key, the way the guide gives it
export GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf "${DEMO}/keys/key2.pub" | cut -d " " -f 2)"

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

unset GITS_ENCRYPTION_SSH_KEY

COMMAND='w diff 2>&1 | has "AUTH" "is it stored with another key"'
EXPECTED_STDOUT="AUTH
is it stored with another key"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "the first key doesn't open them"

# ======================= scenario B =======================

# ---------- 7. from scratch, stored encrypted with the first key ----------

# reset: the key files stay (the same fingerprint), but both keys are taken out of the agent
FP_BEFORE="$(fp key)"

# two more keys in the agent of the test: one with "gits" in its label which is not of the demo,
# one without. reset removes by the label: the first one goes too, the second one stays
ssh-keygen -q -t ed25519 -N "" -C "my-gits-encryption" -f "${WORK}/with_label"
ssh-keygen -q -t ed25519 -N "" -C "something-else" -f "${WORK}/without_label"
ssh-add -q "${WORK}/with_label" "${WORK}/without_label" || fail "ssh-add failed"

COMMAND='/bin/bash "${ENC}/reset_setup.sh" 2>&1 | has "removed from the ssh-agent: gits-os-agent-demo-key" "removed from the ssh-agent: gits-os-agent-demo-key2" "removed from the ssh-agent: my-gits-encryption" "something-else" "not loaded in the ssh-agent of this terminal" "state 0 is ready"; [[ "$(fp key)" == "${FP_BEFORE}" ]]; echo "same key ${?}"; commits; ssh-add -l | cut -d " " -f 3-'
EXPECTED_STDOUT="removed from the ssh-agent: gits-os-agent-demo-key
removed from the ssh-agent: gits-os-agent-demo-key2
removed from the ssh-agent: my-gits-encryption
not loaded in the ssh-agent of this terminal
state 0 is ready
same key 0
0
something-else (ED25519)"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "reset: every key with gits in its label is removed from the agent, the others and the key files stay"

load_keys

COMMAND='cd "${DEMO}/repoa" && w push --yes 2>&1 | has "files pushed"; cd "${DEMO}/repob" && w push --yes 2>&1 | has "files pushed"; forms; with "$(fp key)"'
EXPECTED_STDOUT="files pushed
files pushed
encrypted lines | encrypted lines | encrypted lines | encrypted blob
4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "keys loaded again, push both projects: four files with the first key"

# ---------- 8. rekey ----------

cd "${DEMO}"
COMMITS="$(commits)"

# the server has only the key which opens the files: it can't know the new one
COMMAND='w crypt rekey --storage --yes 2>&1 | has "USAGE" "started without GITS_ENCRYPTION_REKEY_SSH_KEY" "Nothing was changed in the storage"; echo "$(( $(commits) - COMMITS )) commit"'
EXPECTED_STDOUT="USAGE
started without GITS_ENCRYPTION_REKEY_SSH_KEY
Nothing was changed in the storage
0 commit"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey: refused by a server without new keys"

# the new key, as a fingerprint: no file is read
export GITS_ENCRYPTION_REKEY_SSH_KEY="$(fp key2)"

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

unset GITS_ENCRYPTION_REKEY_SSH_KEY

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

export GITS_ENCRYPTION_SSH_KEY="$(fp key2)"

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
export GITS_ENCRYPTION_REKEY_SSH_KEY="$(fp key)"

# this project only (its one :e: file). Line 2 is the key line, the rest is the content
COMMAND='w crypt rekey --rewrap-only --yes 2>&1 | has "rekey --rewrap-only: '"'"'${A}/.env'"'"'" "1 files changed in the storage"; diff "${WORK}/env.before" "${SRC}/${A}/.env" | grep -c "^[<>]"; diff <(sed 2d "${WORK}/env.before") <(sed 2d "${SRC}/${A}/.env") && echo "content identical"'
EXPECTED_STDOUT="rekey --rewrap-only: '${A}/.env'
1 files changed in the storage
2
content identical"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey --rewrap-only: only the key line changed"

unset GITS_ENCRYPTION_REKEY_SSH_KEY
unset GITS_ENCRYPTION_SSH_KEY

# repoa is back on the first key, repob stays on key2
COMMAND='w isinsync; echo "repoa ${?}"; cd "${DEMO}" && with "$(fp key)"; with "$(fp key2)"'
EXPECTED_STDOUT="repoa 0
1
3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after rewrap: the first key opens repoa again"

# ---------- 10. nothing left, wrong arguments ----------

COMMAND='listing "${DEMO}/tmp"; ps -A -o command= | grep -c "[e]ncrypt_os_ssh_agent/server.js"'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no socket, no pid file, no server left by any command"

# not used by the guide, but ssenc takes it too: a public key file, relative to the directory of the command.
# start.sh checks it, and its test encrypts and decrypts with it through the server and ssenc
COMMAND='cd "${DEMO}" && GITS_ENCRYPTION_SSH_KEY=keys/key2.pub w crypt status all 2>&1 | has "encrypted: 4"; cd repoa && GITS_ENCRYPTION_SSH_KEY=../keys/key.pub w isinsync; echo "repoa ${?}"'
EXPECTED_STDOUT="encrypted: 4
repoa 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "a relative path of the public key file works, from both directories"

# stop.sh ran after every command above: the agent is still there, with both keys
COMMAND='ssh-add -l | grep -c "gits-os-agent-demo"'
EXPECTED_STDOUT="2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the agent was not touched: both keys are still loaded"

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
