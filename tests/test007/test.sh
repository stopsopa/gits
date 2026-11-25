#
# Encrypted elements: "SOURCE:e:TARGET" in GITSTORAGELIST means "store this file encrypted".
#
# gits doesn't encrypt by itself and starts no program for it. It connects to the unix socket from
# env var GITSTORAGETENCRYPTIONSOCKET and sends one line per file to the process listening there:
#
#   encode "<plain file>" "<encrypted file>"
#   decode "<encrypted file>" "<plain file>"
#
# What this test needs (all prepared by tests/_lib.sh, everything in tests/test007/tmp/):
#   - the REAL encoder process: submodules/encrypt/examples/socket/server.ts started with --seal, the
#     way "socket-002-encoder_process_on_a_socket" of submodules/encrypt/examples/SUMMARY.md shows it
#   - a demo ssh key in a private ssh-agent (the agent of the developer is never used)
#   - the ssenc binary of the submodule (compiled here when it is not there yet). gits doesn't use it;
#     the test looks with it at the stored files from outside: they have to be ordinary ssenc files
#     which the binary opens with the same key
#   - node >= 22.18, ssh-keygen, ssh-agent, ssh-add, nc
#
# What is tested, in this order:
#
#  1. first diff and push: a new encrypted element is shown in plain text in the diff; push stores it
#     encrypted (ssenc file with a seal), plain elements stay plain, a file name with a quote and a
#     space works, the temporary plain copy (TARGET.hash...) never reaches the storage
#  2. in sync: diff / isinsync say "in sync" although the stored bytes differ from the local ones
#     (they compare decrypted), and a push of unchanged files makes no commit
#  3. one line edited: the diff is in plain text, the local file is in the list of changed files,
#     diff pushes nothing; the push changes in the stored file only the edited line and the seal line
#  4. pull writes the files decrypted
#  5. state decrypts too
#  6. GITSTORAGETENCRYPTIONSOCKET not defined: every command explains it, isinsync exits with 2
#  7. a socket nobody listens on: error, nothing pushed, nothing left behind
#  8. the encoder process has another key: nothing is decrypted, the local file is not overwritten
#     by pull, nothing is pushed
#  9. an element changed from "::" to ":e:" and back: converted by the next push
# 10. the config itself encrypted: "gits init" on another machine restores it decrypted, and
#     refuses without the socket
#
# /bin/bash tests/test007/test.sh
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

# directory of the project in the storage (GITSTORAGETARGETDIR), made from the remote below
D="git@github.com:tmp__repo.git"

# ssenc_build:   compiles submodules/encrypt/rust/target/release/ssenc when it is not there yet
# encoder_start: makes the demo key "key-one", starts the private ssh-agent and loads the key into it,
#                starts the encoder process with that key (tests/encoder/encoder-start.sh) and exports
#                GITSTORAGETENCRYPTIONSOCKET - from here on gits finds the encoder process
ssenc_build
encoder_start key-one

# the project all checks run in (except the last section)
project repo "git@github.com:tmp/repo.git"
cd repo

# The files of the project:
#   .env               three lines, will be stored encrypted; three, to see later that an edit
#                      of one of them changes only that line in the stored file
#   plain.txt          stored as it is
#   we"ird name.txt    a double quote and a space in the name: the path is sent to the encoder
#                      process inside of double quotes, so the quote has to be escaped correctly
printf 'A=1\nB=2\nC=3\n' > .env
echo 'not a secret' > plain.txt
printf 'a "quoted" name\n' > 'we"ird name.txt'

# The config: two elements with ":e:" (encrypted), two with "::" (plain, one of them the config
# itself). The last element is written in two pieces of shell quoting only because of the quote in
# the name; its TARGET is in a subdirectory with a space ("sub dir").
cat <<EEE > .git/gits.sh
GITSTORAGETARGETDIR="${D}"
GITSTORAGELIST=(
    "gits.sh::\$GITSTORAGETARGETDIR/gits.sh"
    "../.env:e:\$GITSTORAGETARGETDIR/.env"
    "../plain.txt::\$GITSTORAGETARGETDIR/plain.txt"
    '../we"ird name.txt:e:'"\$GITSTORAGETARGETDIR/sub dir/we\"ird name.txt"
)
EEE

# LISTING: what the directory of the project has to contain after every command - nothing more
#          (no temporary clone, no .hash... file left behind)
# WEIRD:   the name with the quote, to use it in commands without fighting with quoting
LISTING='.env .git plain.txt we"ird name.txt'
WEIRD='we"ird name.txt'

# ---------- first diff and push ----------

# Nothing is stored yet. The diff shows the new .env as added lines in PLAIN text ("+B=2"), not as
# something encrypted: gits compares plain with plain. Exit code 1: not in sync.
COMMAND='gits diff 2>&1 | has "+B=2"'
EXPECTED_STDOUT="+B=2"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "first diff: new file in plain text"

# what push prints for every copied file: F1 an encrypted element (marked), F2 a plain one (not marked)
F1="'../.env' -> '${D}/.env' (encrypted)"
F2="'../plain.txt' -> '${D}/plain.txt'"

# The first push: .env and the file with the quote go through the encoder process, the others are
# copied as they are. Exit code 0: committed and pushed.
COMMAND='gits push --yes 2>&1 | has "${F1}" "${F2}"'
EXPECTED_STDOUT="${F1}
${F2}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push: encrypted element is marked, plain element is not"

# The directory of the project after push: only the files of the project. The plain copy made for
# the moment of encryption was inside of the temporary clone and is gone with it.
COMMAND='listing'
EXPECTED_STDOUT="${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "after push"

# .env as it is in the storage now ("stored" clones the storage to ${WORK}/look and prints the file):
#   "#ssenc1"   it is a file of the encoder (first line of every ssenc file)
#   "#seal"     it was made with --seal
#   "B=2"       asked for and NOT expected: no plain text of the file is in it
COMMAND='stored "${D}/.env" | has "#ssenc1" "#seal" "B=2"'
EXPECTED_STDOUT="#ssenc1
#seal"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env is the output of the encoder, no plain text in it"

# The other two files in the storage: plain.txt is stored as it is ("not a secret"), the file with
# the quote and the space in its name is an ssenc file - the path with the quote reached the encoder
# process correctly.
COMMAND='stored "${D}/plain.txt"; stored "${D}/sub dir/${WEIRD}" | has "#ssenc1"'
EXPECTED_STDOUT="not a secret
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored plain.txt is plain, file with a quote and a space in the name is encrypted"

# seen from outside: the ssenc binary of submodules/encrypt opens what gits stored, with the same key
# The ssenc binary (another program than the encoder process, written in Rust) decrypts the stored
# file with the same key and prints exactly the three plain lines: what gits stored is not something
# only gits understands.
COMMAND='ssenc decrypt --ssh-key "${WORK}/keys/key-one.pub" -i "${WORK}/look/${D}/.env"'
EXPECTED_STDOUT="A=1
B=2
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env is an ordinary ssenc file: the ssenc binary decrypts it"

# "ssenc inspect" prints how a file was encrypted, without needing a key. Expected:
#   "mode":"lines"   every line encrypted on its own (that is what keeps git diffs of the storage small)
#   "seal":true      --seal was used
#   "type":"ssh"     the key which opens it is an ssh key
COMMAND='ssenc inspect -i "${WORK}/look/${D}/.env" | has "\"format\":\"ssenc1\"" "\"mode\":\"lines\"" "\"seal\":true" "\"type\":\"ssh\""'
EXPECTED_STDOUT='"format":"ssenc1"
"mode":"lines"
"seal":true
"type":"ssh"'
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "stored .env: line by line, sealed, opened by an ssh key"

# the plain copy made for the moment of encryption (TARGET.hash...) never reaches the storage
# All files git tracks in a fresh clone of the storage:
#   first part:  names with "hash" in them - nothing may come back (has prints nothing)
#   second part: the number of files, 4 = the four elements of the list and nothing else
COMMAND='storage "${WORK}/look" && cd "${WORK}/look" && git ls-files | has "hash"; git ls-files | wc -l | tr -d " "'
EXPECTED_STDOUT="4"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "four files in the storage, no temporary files"

# the stored (encrypted) .env of this first push is kept as "v1", to compare with the next version
stored "${D}/.env" > "${WORK}/v1"

# ---------- in sync ----------

# Nothing was edited since the push. The stored .env is encrypted and the local one is plain, so the
# bytes differ - but gits decrypts the stored one first and compares that. Exit code 0: in sync.
COMMAND='gits diff 2>&1 | has "files are in sync"'
EXPECTED_STDOUT="files are in sync"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff in sync"

# The same question for scripts: no output at all, exit code 0 = in sync.
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "isinsync in sync"

# A push when nothing was edited. Encrypting the same text again would give different bytes every
# time (and a commit with nothing new in it), so gits doesn't encrypt what didn't change:
# the storage still has 1 commit.
COMMAND='gits push --yes > /dev/null 2>&1; storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "push of unchanged files: no commit"

# ---------- one line edited: the diff is in plain text ----------

# the middle line of the local .env is edited: B=2 -> B=22
printf 'A=1\nB=22\nC=3\n' > .env

# no output, exit code 1 = not in sync any more
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "isinsync after an edit"

# the two lines of a normal git diff: what is stored (-) and what is here (+), both in plain text
F1="-B=2
+B=22"

# nothing encrypted is shown, the other files are not there
# The diff of an encrypted element reads like the diff of a plain one: the two lines of F1.
# Asked for and NOT expected:
#   "#ssenc1"     nothing encrypted is shown
#   "plain.txt"   files which didn't change are not in the diff
# Exit code 1: not in sync.
COMMAND='gits diff 2>&1 | has "${F1}" "#ssenc1" "plain.txt"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after an edit is in plain text"

# The end of the output of the same diff, from "changed files:" to "final url": the block with
# absolute paths of the local files which differ. For the encrypted element it is the plain local
# file ${WORK}/repo/.env, and it is the only one.
COMMAND='gits diff 2>&1 | sed -n "/^changed files:/,/^final url/p"'
EXPECTED_STDOUT="changed files:
  ${WORK}/repo/.env

final url ${GITSTORAGESOURCE} (directory ${D})"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "diff after an edit: the local file of the encrypted element is in the list of changed files"

# the commit with decrypted files stays in the temporary clone
# To show the diff gits commits the decrypted files inside of its temporary clone. That commit
# must never be pushed (it would put plain text into the storage): still 1 commit.
COMMAND='storage_commits'
EXPECTED_STDOUT="1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "diff doesn't push"

# The push of the edit: exit code of gits 0 (printed by echo), and now 2 commits in the storage.
COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; storage_commits'
EXPECTED_STDOUT="0
2"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second push: commit"

# the stored .env after the second push is kept as "v2"
stored "${D}/.env" > "${WORK}/v2"

# the existing stored file is the "previous version" for the encoder: only the edited line differs,
# and the #seal line (--seal: one line which covers the whole file) - 2 lines, each as "<" and as ">"
# v1 against v2, the two encrypted versions. Three numbers:
#   4   lines of the diff which start with < or >: 2 lines changed, each shown once as old and once as new
#   2   of those are the #seal line (old and new) - so the other changed line is the edited one,
#       and the lines A=1 and C=3 are byte for byte what they were
#   1   file in the last commit of the storage: only .env, the files which were not edited are not in it
# ("|| true": diff exits with 1 when the files differ, that is expected here)
COMMAND='{ diff "${WORK}/v1" "${WORK}/v2" || true; } | grep -c "^[<>]"; { diff "${WORK}/v1" "${WORK}/v2" || true; } | grep -c "^[<>] #seal"; git -C "${WORK}/look" show --stat --format= HEAD | grep -c "|"'
EXPECTED_STDOUT="4
2
1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "only the edited line changed in the stored file, only .env is in the second commit"

# The ssenc binary decrypts the new version too, and gives the edited text.
COMMAND='ssenc decrypt --ssh-key "${WORK}/keys/key-one.pub" -i "${WORK}/v2"'
EXPECTED_STDOUT="A=1
B=22
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "second push: the ssenc binary decrypts the new version"

# ---------- pull decrypts ----------

# both encrypted elements are removed locally, pull has to bring them back
rm .env "${WEIRD}"

# pull: exit code 0, then the content of both files - plain text, as they were pushed - and the
# listing: only the files of the project (the decrypted copy made in the clone is gone with it).
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

# "gits state" started one directory above finds the project and compares it the same way
# (decrypted): 1 project in sync, exit code 0.
COMMAND='cd "${WORK}" && gits state 2>&1 | has "COUNT_SUCCESS : 1"'
EXPECTED_STDOUT="COUNT_SUCCESS : 1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "state: in sync"

# another edit of the local .env, the last line this time
printf 'A=1\nB=22\nC=33\n' > .env

# state now shows the git status of the project with .env as modified (not as a file which is
# "always different because it is encrypted"). Exit code 1: something is not in sync.
COMMAND='cd "${WORK}" && gits state 2>&1 | has "modified:   ${D}/.env"'
EXPECTED_STDOUT="modified:   ${D}/.env"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "state after an edit"

# the edit is taken back: local files are again what is stored
printf 'A=1\nB=22\nC=3\n' > .env

# ---------- no socket defined: explained, nothing happens ----------

# the env var is gone: gits has no idea where the encoder process is (it still runs)
unset GITSTORAGETENCRYPTIONSOCKET

# every command which has to decrypt or encrypt
for CMD in diff "push --yes" "pull --yes"; do
  # it doesn't guess a socket and doesn't treat the element as plain: it says which env var is
  # missing, exit code 1
  COMMAND="gits ${CMD} 2>&1 | has 'env var GITSTORAGETENCRYPTIONSOCKET is not defined'"
  EXPECTED_STDOUT="env var GITSTORAGETENCRYPTIONSOCKET is not defined"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "${CMD} without socket"
done

# isinsync: 0 is "in sync", 1 is "not in sync" - here it can't tell, that is exit code 2 (an error),
# so that a script doesn't take it for "not in sync".
COMMAND='gits isinsync 2> /dev/null'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="2"
test "isinsync without socket is an error"

# ---------- nobody listens ----------

# the env var points to a socket file which doesn't exist
export GITSTORAGETENCRYPTIONSOCKET="${WORK}/nobody.sock"

# the error names the env var and the path it was given
F1="can't connect to the encoder process on socket GITSTORAGETENCRYPTIONSOCKET=>${WORK}/nobody.sock<"

# gits can't connect: error, exit code 1.
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "socket nobody listens on"

# After all those failed commands: still 2 commits in the storage, and the directory of the project
# has only its files (every temporary clone was removed, also after an error).
COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "nothing was pushed without the encoder, nothing left behind"

# ---------- the encoder has another key: nothing is decrypted, nothing is overwritten, nothing is pushed ----------

# The encoder process is restarted with another demo key ("key-two", made now). The stored files
# were encrypted for key-one: this process can't open them. And the local .env gets an edit,
# to see whether anything overwrites it.
encoder_start key-two
printf 'local edit\n' > .env

# AUTH is the kind of error the encoder process replies with when the key doesn't open the file
F1="can't decrypt '${D}/.env': AUTH"

# diff has to decrypt the stored .env first: the encoder process refuses, gits reports it, exit code 1.
# (It is not treated as "stored plain": that is only done for a file which is not an ssenc file at all.)
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, diff"

# pull fails the same way, exit code 1.
COMMAND='gits pull --yes 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, pull"

# The local .env still has "local edit": a failed decryption wrote nothing over it.
COMMAND='cat .env'
EXPECTED_STDOUT="local edit"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrong key, pull: local file untouched"

# push needs to decrypt the stored file too (to see whether it changed): it fails, exit code 1.
COMMAND='gits push --yes > /dev/null 2>&1'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "wrong key, push"

# Nothing reached the storage (still 2 commits), nothing was left in the directory of the project.
COMMAND='storage_commits; listing'
EXPECTED_STDOUT="2
${LISTING}"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "wrong key, push: nothing pushed, nothing left behind"

# the local edit is taken back
printf 'A=1\nB=22\nC=3\n' > .env

# and the encoder process is restarted with the right key again
encoder_start key-one

# everything is as it was before this section: no output, exit code 0
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "in sync again with the right key"

# ---------- an element changed from "::" to ":e:": stored plain until the next push ----------

# The element of plain.txt is changed in the config from "::" to ":e:". In the storage the file is
# still plain. (sed -i.bak + rm: the form of "edit in place" which works on macOS and on Linux)
sed -i.bak 's|"../plain.txt::|"../plain.txt:e:|' .git/gits.sh && rm .git/gits.sh.bak

# the note gits prints for such a file
F1="'${D}/plain.txt' is marked :e: but it is stored not encrypted"

# exit code 1: the config changed
# diff asks the encoder process to decrypt plain.txt, the reply is "this is not an encrypted file",
# and gits takes the stored file as plain and says so (F1) instead of failing.
# Exit code 1 although plain.txt itself didn't change: the config did, and it is stored too.
COMMAND='gits diff 2>&1 | has "${F1}"'
EXPECTED_STDOUT="${F1}"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "plain -> encrypted, diff: note"

# The next push converts it: exit code 0, and the stored plain.txt is now an ssenc file
# ("not a secret" is asked for and must not be in it any more).
COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/plain.txt" | has "#ssenc1" "not a secret"'
EXPECTED_STDOUT="0
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "plain -> encrypted, push: stored encrypted now"

# no output, exit code 0: in sync after the conversion
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "plain -> encrypted: in sync after push"

# ---------- and back ----------

# the other direction: the element is changed back from ":e:" to "::"
sed -i.bak 's|"../plain.txt:e:|"../plain.txt::|' .git/gits.sh && rm .git/gits.sh.bak

# push: exit code 0, and the stored plain.txt is plain text again.
COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/plain.txt"'
EXPECTED_STDOUT="0
not a secret"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted -> plain: stored plain again"

# no output, exit code 0: in sync
COMMAND='gits isinsync'
EXPECTED_STDOUT=""
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted -> plain: in sync after push"

# ---------- the config itself can be encrypted, init on another machine restores it decrypted ----------

# the element which stores the config itself becomes an encrypted one
sed -i.bak 's|"gits.sh::|"gits.sh:e:|' .git/gits.sh && rm .git/gits.sh.bak

# push: exit code 0, and gits.sh in the storage is an ssenc file ("GITSTORAGELIST", a word of the
# plain config, is asked for and must not be in it).
COMMAND='gits push --yes > /dev/null 2>&1; echo "${?}"; stored "${D}/gits.sh" | has "#ssenc1" "GITSTORAGELIST"'
EXPECTED_STDOUT="0
#ssenc1"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "encrypted config in the storage"

# "Another machine": a second, empty project with the same remote. It has no config; "gits init"
# looks for one in the storage, in the directory made from the remote.
cd ..
project two "git@github.com:tmp/repo.git"
cd two

# init without the socket (the env var empty for this one command): the stored config is encrypted,
# gits can't use it and must not write it as it is into .git. It explains, exit code 1.
COMMAND='GITSTORAGETENCRYPTIONSOCKET="" gits init 2>&1 | has "is encrypted, define env var GITSTORAGETENCRYPTIONSOCKET"'
EXPECTED_STDOUT="is encrypted, define env var GITSTORAGETENCRYPTIONSOCKET"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "init, encrypted config, no socket"

# After the refused init the project has only .git: no half made config.
COMMAND='listing'
EXPECTED_STDOUT=".git"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init, encrypted config, no socket: nothing created"

# init with the socket: exit code 0, and diff prints nothing = the restored .git/gits.sh is the
# same plain text as the config of the first project.
COMMAND='gits init > /dev/null 2>&1; echo "${?}"; diff .git/gits.sh ../repo/.git/gits.sh'
EXPECTED_STDOUT="0"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "init, encrypted config: restored decrypted"

# With that config pull works on the other machine: exit code 0, .env arrives decrypted.
COMMAND='gits pull --yes > /dev/null 2>&1; echo "${?}"; cat .env'
EXPECTED_STDOUT="0
A=1
B=22
C=3"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "pull on the other machine"
