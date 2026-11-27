#
# Every env var of the demo examples/encrypt/ENCRYPT_PROCESS.md, in one place.
#
# Not called by itself: gits.sh, keys.sh, start.sh, stop.sh and reset_setup.sh source it, after they found
# their own directory (${_DIR}, the directory examples/encrypt/):
#
#   source "${_DIR}/env.sh"
#
# A variable which is already defined in the terminal wins: GITS_ENCRYPTION_SSH_KEY=... /bin/bash gits.sh diff
#

# Where everything generated goes: gits_source/, repoa/, repob/, tmp/, server.log.
# Here, next to the scripts. The test tests/test016 points it to its own directory.
# The keys, the sockets and the pid files are in its directory tmp/ (${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp).
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
# opens what is stored. The private key file, its public key is next to it (<file>.pub).
# Read only by start.sh (loads it into the agent) and server.ts, not by gits.
# keys.sh creates two in tmp/: "key" (the default below) and "key2".
# The value is the path of the file exactly as it is used, nothing is added to it: a full path,
# or one relative to the directory the command is started in. To use the other key for one
# command, override only this variable:
#   GITS_ENCRYPTION_SSH_KEY=tmp/key2 /bin/bash gits.sh crypt encrypt all --yes
export GITS_ENCRYPTION_SSH_KEY="${GITS_ENCRYPTION_SSH_KEY:-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/key}"

# Empty by default, and it should stay empty. It exists only for one example of
# ENCRYPT_PROCESS.md, step 7 "gits crypt rekey": the only operation which needs two keys at the
# same time. GITS_ENCRYPTION_SSH_KEY opens what is stored, this one is the key the stored files
# get in its place. Empty: the server refuses rekey requests.
# The value is the path of the private key file exactly as it is used, nothing is added to it:
# a full path, or one relative to the directory the command is started in. Given only in the
# command itself:
#   GITS_ENCRYPTION_REKEY_SSH_KEY=tmp/key2 /bin/bash gits.sh crypt rekey --storage --yes
export GITS_ENCRYPTION_REKEY_SSH_KEY="${GITS_ENCRYPTION_REKEY_SSH_KEY:-}"
	# it is not consumed by gits itself but by 
	# 	- start.sh to load to ssh-add and 
	# 	- server.ts to call ssenc with "--ssh-key", currentKey(), "--new-ssh-key"

# Socket of the ssh-agent which start.sh starts only for the demo: the key above is loaded into
# this one, never into your own agent.
GITS_DEMO_AGENT="${GITS_DEMO_AGENT:-${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}/tmp/agent.sock}"

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
# For the demo encrypt.sh copies it to examples/encrypt/bin/ssenc, from
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
