#
# Every env var of the demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md, in one place.
#
# Not called by itself: gits.sh, keys.sh, start.sh, stop.sh and reset_setup.sh source it, after they found
# their own directory (${_DIR}, the directory examples/encrypt_os_ssh_agent/):
#
#   source "${_DIR}/env.sh"
#
# A variable which is already defined in the terminal wins: GITS_ENCRYPTION_SSH_KEY=... /bin/bash gits.sh diff
#
# There is no variable for an ssh-agent here: this demo starts none. The agent is the one of
# your terminal, SSH_AUTH_SOCK, and the keys have to be loaded into it by you (ssh-add).
#

# Where everything generated goes: gits_source/, repoa/, repob/, keys/, tmp/, server.log.
# Here, next to the scripts. The test tests/test018 points it to its own directory.
export GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES:-${_DIR}}"

# The storage of the demo: a local git repository created by reset_setup.sh. gits reads it from
# GITS_SOURCE. Deliberately NOT "the one of the terminal wins" (no ${GITS_SOURCE:-...} here):
# GITS_SOURCE of your terminal is your real storage, the demo must never push there, and
# reset_setup.sh removes this directory. To have it somewhere else: GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES.
export GITS_SOURCE="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/gits_source"

# The second variable gits reads: the unix socket it sends encode / decode requests to.
# start.sh starts the server on it, stop.sh removes it. At most about 100 characters.
# Defined as an empty text: no socket. gits.sh starts gits without it (and starts no server):
#   GITS_ENCRYPTION_SOCKET= /bin/bash gits.sh push --yes
export GITS_ENCRYPTION_SOCKET="${GITS_ENCRYPTION_SOCKET-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/ssenc.sock}"

# The one variable which says which ssh key is used: everything is encrypted with it, and it
# opens what is stored. The key itself has to be loaded in the agent of your terminal
# (SSH_AUTH_SOCK), this variable only says WHICH of the keys loaded there: its fingerprint,
#
#   SHA256:Gr0pY4nDEN8SSFajggNO3IBDdQlIx1v+kSU7buMeTWk
#
# the second word of what "ssh-keygen -lf <file>.pub" and "ssh-add -l" print. Not a path:
# once the key is loaded (ssh-add) no file of it is needed, not even the public one.
# The value goes to ssenc exactly as it is (--ssh-key).
# Read only by server.ts, not by gits.
#
# The default: the fingerprint of the key "key" which keys.sh created in keys/, read from its
# public key file (the demo can't know the fingerprint of a key it generates in advance; with
# your own key write the fingerprint itself here). No such file yet: empty, and the server says so.
# The other key of the demo, for one command:
#   GITS_ENCRYPTION_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt encrypt all --yes
export GITS_ENCRYPTION_SSH_KEY="${GITS_ENCRYPTION_SSH_KEY:-$(ssh-keygen -lf "${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/keys/key.pub" 2> /dev/null | cut -d " " -f 2)}"

# Empty by default, and it should stay empty. It exists only for one example of
# ENCRYPT_PROCESS.md, step 7 "gits crypt rekey": the only operation which needs two keys at the
# same time. GITS_ENCRYPTION_SSH_KEY opens what is stored, this one is the key the stored files
# get in its place. Empty: the server refuses rekey requests. A fingerprint too, and this key
# has to be loaded in the agent too. Given only in the command itself:
#   GITS_ENCRYPTION_REKEY_SSH_KEY="$(ssh-keygen -lf keys/key2.pub | cut -d " " -f 2)" /bin/bash gits.sh crypt rekey --storage --yes
export GITS_ENCRYPTION_REKEY_SSH_KEY="${GITS_ENCRYPTION_REKEY_SSH_KEY:-}"

# Log of the server: one line per file, "encrypted <file> -> <file>" or "decrypted <file> -> <file>".
# Defined as an empty text (GITS_DEMO_LOG=""): nothing is logged.
GITS_DEMO_LOG="${GITS_DEMO_LOG-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/server.log}"

# The program which really encrypts: server.js starts it for every request.
#
# It is the Rust binary "ssenc" of https://github.com/stopsopa/encrypt, in a checkout of it:
#
#   rust/target/release/ssenc        built by: /bin/bash rust/compile.sh   (cargo build --release)
#
# (not rust/bin/ssenc: that one is a shell script which starts the file above.)
# One file, no other file of that repository is needed next to it.
#
# For the demo encrypt.sh copies it to examples/encrypt_os_ssh_agent/bin/ssenc, from
# __linked/STOPSOPA__encrypt/STOPSOPA__encrypt or from submodules/encrypt (GITS_DEMO_ENCRYPT).
# For real: install that file wherever you want and point this variable to it,
# a path (GITS_DEMO_SSENC=/usr/local/bin/ssenc) or a name found in PATH (GITS_DEMO_SSENC=ssenc).
# encrypt.sh copies nothing then.
export GITS_DEMO_SSENC="${GITS_DEMO_SSENC:-${_DIR}/bin/ssenc}"

# Only for encrypt.sh: the checkout of the encrypt repository the binary above is copied from.
# Not defined: __linked/STOPSOPA__encrypt/STOPSOPA__encrypt, then submodules/encrypt.
GITS_DEMO_ENCRYPT="${GITS_DEMO_ENCRYPT:-}"

# The gits binary which gits.sh starts: the one compiled here (/bin/bash compile.sh).
GITS_DEMO_BIN="${GITS_DEMO_BIN:-$(ls "${_DIR}"/../../bin/*/gits 2> /dev/null | head -n 1)}"
