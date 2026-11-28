#
# Every env var of the demo examples/base64_md5/ENCRYPT_PROCESS.md, in one place.
#
# Not called by itself: gits.sh, start.sh, stop.sh and reset_setup.sh source it, after they found
# their own directory (${_DIR}, the directory examples/base64_md5/):
#
#   source "${_DIR}/env.sh"
#
# A variable which is already defined in the terminal wins: GITS_DEMO_LOG="" /bin/bash gits.sh diff
#
# No ssh key, no ssh-agent, no binary of the encrypt repository here: the "encryption" of this
# demo is base64 with an md5 checksum, done by server.ts itself. It protects nothing. The demo
# shows that gits doesn't care what is behind the socket.
#

# Where everything generated goes: gits_source/, GITS_PULL_TO_SYNC/, repoa/, repob/, tmp/, server.log.
# Here, next to the scripts. The test tests/test019 points it to its own directory.
export GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES:-${_DIR}}"

# The storage of the demo: a local git repository created by reset_setup.sh. gits reads it from
# GITS_SOURCE. Deliberately NOT "the one of the terminal wins" (no ${GITS_SOURCE:-...} here):
# GITS_SOURCE of your terminal is your real storage, the demo must never push there, and
# reset_setup.sh removes this directory.
export GITS_SOURCE="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/gits_source"

# Where gits keeps its clone of the storage between the commands (fetch + reset + clean in
# place of a fresh clone every time). Not "the one of the terminal wins" for the same reason.
export GITS_PULL_TO_SYNC="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/GITS_PULL_TO_SYNC"

# The unix socket gits sends its encode / decode requests to. start.sh starts the server on it,
# stop.sh removes it. At most about 100 characters.
# Defined as an empty text: no socket. gits.sh starts gits without it (and starts no server):
#   GITS_ENCRYPTION_SOCKET= /bin/bash gits.sh push --yes
export GITS_ENCRYPTION_SOCKET="${GITS_ENCRYPTION_SOCKET-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/base64_md5.sock}"

# The script which tells gits whether a stored file is an encoded one. gits has a built-in rule
# for that, but it knows only the files of https://github.com/stopsopa/encrypt ("#ssenc1 ...").
# The format of this demo is another one, so gits is given the rule from outside:
#   <script> <file>      exit code 0: encoded (and it prints "md5:<checksum>"), 1: not
# Without this variable gits would take every stored file of the demo for a plain one.
# Defined as an empty text (GITS_ENCRYPTION_DETECT= /bin/bash gits.sh crypt status): the built-in rule.
export GITS_ENCRYPTION_DETECT="${GITS_ENCRYPTION_DETECT-${_DIR}/detect.sh}"

# Log of the server: one line per file, "encoded <file> -> <file>" or "decoded <file> -> <file>".
# Defined as an empty text (GITS_DEMO_LOG=""): nothing is logged.
GITS_DEMO_LOG="${GITS_DEMO_LOG-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/server.log}"

# The gits binary which gits.sh starts: the one compiled here (/bin/bash compile.sh).
GITS_DEMO_BIN="${GITS_DEMO_BIN:-$(ls "${_DIR}"/../../bin/*/gits 2> /dev/null | head -n 1)}"
