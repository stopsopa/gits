#
# The demo examples/base64_md5 (its ENCRYPT_PROCESS.md): gits with an encoder process which has
# nothing to do with https://github.com/stopsopa/encrypt. Its server encodes a file as one line,
#
#   <md5 of the base64 text>:<base64 of the content>
#
# no key, no ssh-agent, no binary. What is tested is the decoupling: gits knows only the socket
# protocol (encode / decode, "error MALFORMED" = not an encoded file) and the script of
# GITS_ENCRYPTION_DETECT (is a stored file an encoded one), so it has to work the same.
# Everything is created in tests/test019/tmp/demo (GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES).
#
# What is tested, in this order:
#
#   1. reset_setup.sh: storage, repoa, repob; nothing is stored yet
#   2. detect.sh by itself: exit code 0 + "md5:..." for an encoded file, 1 for plain files, also
#      for one which only looks like an encoded one (wrong md5), 2 without an argument
#   3. no GITS_ENCRYPTION_SOCKET: ':e:' is ignored, push stores the files as they are
#   4. with the socket: a ':e:' file stored plain is used as it is (in sync; the server answers
#      "error MALFORMED"), push encodes, "gits crypt encrypt" encodes what is still plain.
#      The stored file is exactly <md5>:<base64> and decodes with the tools of the system
#   5. gits crypt status: "encrypted" with [md5:...] of each file
#   6. diff sees a local change (compared decoded), pull brings text and binary files back
#   7. no socket + stored encoded: an error for diff, push, pull (isinsync: exit code 2)
#   8. gits crypt decrypt --storage --yes: everything plain again, one commit; then
#      gits crypt encrypt all --yes: everything encoded again
#   9. gits crypt rekey: refused by the server (there are no keys), nothing changed
#  10. without GITS_ENCRYPTION_DETECT gits falls back to its built-in rule and takes the encoded
#      files for plain ones: that is what the variable is for. A script which fails stops gits
#  11. after every command no server runs and no socket is left
#
# Needs: the compiled binary (/bin/bash compile.sh), Node.js >= 22.18.
#
# /bin/bash tests/test019/test.sh
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


ENC="${_ROOT}/examples/base64_md5"
DEMO="${WORK}/demo"

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

# md5 of stdin, with the tool of this system
function md5_of {
  if command -v md5sum > /dev/null; then
    md5sum | cut -d " " -f 1
  else
    md5 -q
  fi
}

# form <file in the storage>: how it is stored, decided here with nothing of the demo:
# one line "<md5>:<base64>" where the md5 is the one of the base64 text
function form {
  local FILE="${SRC}/${1}"
  local LINE
  IFS= read -r LINE < "${FILE}"
  if [[ "$(wc -l < "${FILE}" | tr -d " ")" == "1" && "${LINE}" =~ ^([0-9a-f]{32}):([A-Za-z0-9+/]*=*)$ && "$(printf "%s" "${BASH_REMATCH[2]}" | md5_of)" == "${BASH_REMATCH[1]}" ]]; then
    echo "encoded"
  else
    echo "plain"
  fi
}

function forms {
  echo "$(form "${A}/.env") | $(form "${B}/.env.local") | $(form "${B}/secrets/token.txt") | $(form "${B}/secrets/cert.bin")"
}

function commits {
  git -C "${SRC}" rev-list --count --all 2> /dev/null || echo 0
}

# ---------- 1. state 0 ----------

COMMAND='/bin/bash "${ENC}/reset_setup.sh" 2>&1 | has "state 0 is ready"; listing "${DEMO}"; commits'
EXPECTED_STDOUT="state 0 is ready
GITS_PULL_TO_SYNC gits_source repoa repob
0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "reset_setup.sh: storage, two projects, nothing stored"

COMMAND='cd "${DEMO}" && w crypt status all 2>&1 | has "missing    ${A}/.env" "missing    ${B}/secrets/cert.bin" "encrypted: 0, plain: 0, not stored yet: 4"'
EXPECTED_STDOUT="missing    ${A}/.env
missing    ${B}/secrets/cert.bin
encrypted: 0, plain: 0, not stored yet: 4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt status all: four :e: files, not stored yet"

# ---------- 2. detect.sh by itself ----------

mkdir -p "${WORK}/detect"
printf "hello\n" > "${WORK}/detect/plain.txt"
# base64 of "hello\n" is aGVsbG8K
printf "%s:aGVsbG8K\n" "$(printf "aGVsbG8K" | md5_of)" > "${WORK}/detect/encoded.txt"
printf "00000000000000000000000000000000:aGVsbG8K\n" > "${WORK}/detect/wrong_md5.txt"
printf "%s:aGVsbG8K\nsecond line\n" "$(printf "aGVsbG8K" | md5_of)" > "${WORK}/detect/two_lines.txt"
head -c 64 /dev/urandom > "${WORK}/detect/binary.bin"

COMMAND='for NAME in encoded.txt plain.txt wrong_md5.txt two_lines.txt binary.bin nothing; do /bin/bash "${ENC}/detect.sh" "${WORK}/detect/${NAME}"; echo "${NAME} ${?}"; done; /bin/bash "${ENC}/detect.sh" 2> /dev/null; echo "no argument ${?}"'
EXPECTED_STDOUT="md5:$(printf "aGVsbG8K" | md5_of)
encoded.txt 0
plain.txt 1
wrong_md5.txt 1
two_lines.txt 1
binary.bin 1
nothing 1
no argument 2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "detect.sh: 0 and the md5 for an encoded file, 1 for everything else"

# ---------- 3. no socket: ':e:' is ignored ----------

cd "${DEMO}/repoa"

COMMAND='plain push --yes 2>&1 | has "GITS_ENCRYPTION_SOCKET is not defined: '"'"':e:'"'"' is ignored" "WITHOUT ENCRYPTION, although marked '"'"':e:'"'"':" "files pushed"; form "${A}/.env"; cmp .env "${SRC}/${A}/.env" && echo identical'
EXPECTED_STDOUT="GITS_ENCRYPTION_SOCKET is not defined: ':e:' is ignored
WITHOUT ENCRYPTION, although marked ':e:':
files pushed
plain
identical"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "no socket: push stores the :e: file as it is"

# ---------- 4. with the socket ----------

# stored plain, marked :e:: the server answers "error MALFORMED" to decode, gits uses the file as it is
COMMAND='w diff 2>&1 | has "is marked :e: but it is stored not encrypted" "files are in sync"; grep -c "error decode .*not a base64_md5 file" "${DEMO}/server.log"'
EXPECTED_STDOUT="is marked :e: but it is stored not encrypted
files are in sync
1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "socket + stored plain: MALFORMED from the server, used as it is"

COMMAND='w crypt status 2>&1 | has "plain      ${A}/.env" "encrypted: 0, plain: 1, not stored yet: 0"; w crypt encrypt 2>&1 | has "would change in the storage" "  ${A}/.env"; form "${A}/.env"'
EXPECTED_STDOUT="plain      ${A}/.env
encrypted: 0, plain: 1, not stored yet: 0
would change in the storage
  ${A}/.env
plain"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt status: plain; crypt encrypt without --yes: a list, nothing changed"

cd "${DEMO}/repob"

COMMAND='w push --yes 2>&1 | has "files pushed"; forms'
EXPECTED_STDOUT="files pushed
plain | encoded | encoded | encoded"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push with the socket: repob stored encoded (text and binary), repoa still plain"

cd "${DEMO}/repoa"

COMMAND='w crypt encrypt --yes 2>&1 | has "encrypt: '"'"'${A}/.env'"'"'" "1 files changed in the storage"; forms; head -n 1 .env'
EXPECTED_STDOUT="encrypt: '${A}/.env'
1 files changed in the storage
encoded | encoded | encoded | encoded
API_KEY=repoa-abc123"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt encrypt --yes: the plain one is encoded in the storage, the local file stays"

# the stored file, taken apart with the tools of the system only: <md5>:<base64>
COMMAND='STORED="$(cat "${SRC}/${A}/.env")"; [[ "$(printf "%s" "${STORED#*:}" | md5_of)" == "${STORED%%:*}" ]] && echo "md5 matches"; printf "%s" "${STORED#*:}" | base64 -d | cmp - .env && echo "base64 is the local file"; wc -l < "${SRC}/${A}/.env" | tr -d " "'
EXPECTED_STDOUT="md5 matches
base64 is the local file
1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "the stored file is one line, <md5 of the base64>:<base64 of the content>"

# ---------- 5. crypt status ----------

COMMAND='cd "${DEMO}" && w crypt status all 2>&1 | has "encrypted  ${A}/.env  [md5:$(cut -d : -f 1 "${SRC}/${A}/.env")]" "encrypted  ${B}/secrets/cert.bin  [md5:$(cut -d : -f 1 "${SRC}/${B}/secrets/cert.bin")]" "encrypted: 4, plain: 0, not stored yet: 0"; w crypt status --storage 2>&1 | has "encrypted: 4, plain: 0, not stored yet: 0"'
EXPECTED_STDOUT="encrypted  ${A}/.env  [md5:$(cut -d : -f 1 "${SRC}/${A}/.env")]
encrypted  ${B}/secrets/cert.bin  [md5:$(cut -d : -f 1 "${SRC}/${B}/secrets/cert.bin")]
encrypted: 4, plain: 0, not stored yet: 0
encrypted: 4, plain: 0, not stored yet: 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt status: four encoded, each with what detect.sh printed"

# ---------- 6. diff, pull ----------

COMMAND='w isinsync; echo "in sync ${?}"; echo "API_KEY=changed" > .env; w diff 2>&1 | has "-API_KEY=repoa-abc123" "+API_KEY=changed"; w pull --yes 2>&1 | has "files pulled"; head -n 1 .env'
EXPECTED_STDOUT="in sync 0
-API_KEY=repoa-abc123
+API_KEY=changed
files pulled
API_KEY=repoa-abc123"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff compares decoded, pull brings the stored content back"

COMMAND='cd "${DEMO}/repob" && cp secrets/cert.bin "${WORK}/cert.before" && rm secrets/cert.bin .env.local && w pull --yes 2>&1 | has "files pulled"; cmp secrets/cert.bin "${WORK}/cert.before" && cat .env.local'
EXPECTED_STDOUT="files pulled
STRIPE_KEY=repob-sk_test_123"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull: a binary and a text file come back byte for byte"

# ---------- 7. no socket + stored encoded ----------

for CMD in diff "push --yes" "pull --yes"; do
  COMMAND="plain ${CMD} 2>&1 | has 'is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined'; head -n 1 .env; form '${A}/.env'"
  EXPECTED_STDOUT="is stored encrypted but env var GITS_ENCRYPTION_SOCKET is not defined
API_KEY=repoa-abc123
encoded"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "no socket + stored encoded: ${CMD} refuses, nothing touched"
done

COMMAND='plain isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "no socket + stored encoded: isinsync 2"

# ---------- 8. decrypt the whole storage, encrypt all ----------

COMMITS="$(commits)"

COMMAND='cd "${DEMO}" && w crypt decrypt --storage --yes 2>&1 | has "4 files changed in the storage"; forms; echo "$(( $(commits) - COMMITS )) commit"; cmp repoa/.env "${SRC}/${A}/.env" && cmp repob/secrets/cert.bin "${SRC}/${B}/secrets/cert.bin" && echo identical; cd repoa && plain isinsync; echo "without the socket ${?}"'
EXPECTED_STDOUT="4 files changed in the storage
plain | plain | plain | plain
1 commit
identical
without the socket 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt decrypt --storage --yes: everything plain, one commit, gits works without the socket"

COMMAND='cd "${DEMO}" && w crypt encrypt all --yes 2>&1 | has "4 files changed in the storage"; forms; cd repoa && w isinsync; echo "repoa ${?}"'
EXPECTED_STDOUT="4 files changed in the storage
encoded | encoded | encoded | encoded
repoa 0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt encrypt all --yes: everything encoded again"

# ---------- 9. rekey ----------

COMMITS="$(commits)"

COMMAND='cd "${DEMO}" && w crypt rekey --storage --yes 2>&1 | has "USAGE" "there are no keys in base64_md5" "Nothing was changed in the storage"; echo "$(( $(commits) - COMMITS )) commit"; forms'
EXPECTED_STDOUT="USAGE
there are no keys in base64_md5
Nothing was changed in the storage
0 commit
encoded | encoded | encoded | encoded"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "crypt rekey: refused by the server, nothing changed"

# ---------- 10. GITS_ENCRYPTION_DETECT ----------

# without the variable: the built-in rule of gits (#ssenc1 ...) doesn't know this format
COMMAND='cd "${DEMO}" && GITS_ENCRYPTION_DETECT= w crypt status all 2>&1 | has "encrypted: 0, plain: 4, not stored yet: 0"; cd repoa && GITS_ENCRYPTION_DETECT= plain isinsync; echo "no socket, no script ${?}"'
EXPECTED_STDOUT="encrypted: 0, plain: 4, not stored yet: 0
no socket, no script 1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "without GITS_ENCRYPTION_DETECT gits takes the encoded files for plain ones"

printf "echo broken >&2\nexit 7\n" > "${WORK}/broken.sh"

COMMAND='GITS_ENCRYPTION_DETECT="${WORK}/broken.sh" w crypt status 2>&1 | has "GITS_ENCRYPTION_DETECT: script >${WORK}/broken.sh< failed" "it ended with 7): broken"; GITS_ENCRYPTION_DETECT="${WORK}/nothing.sh" w crypt status 2>&1 | has "GITS_ENCRYPTION_DETECT: script >${WORK}/nothing.sh< doesn'"'"'t exist"'
EXPECTED_STDOUT="GITS_ENCRYPTION_DETECT: script >${WORK}/broken.sh< failed
it ended with 7): broken
GITS_ENCRYPTION_DETECT: script >${WORK}/nothing.sh< doesn't exist"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "a detection script which fails, or doesn't exist: gits stops and says so"

# ---------- 11. nothing left ----------

COMMAND='ls -A "${DEMO}/tmp" | wc -l | tr -d " "; ps -A -o command= | grep -c "[b]ase64_md5/server.ts"'
EXPECTED_STDOUT="0
0"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no socket, no pid file, no server left by any command"

/bin/bash "${ENC}/stop.sh"
