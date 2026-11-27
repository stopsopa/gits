#
# Every env var of the demo examples/encrypt/ENCRYPT_PROCESS.md, in one place.
#
# Not called by itself: gits.sh, keys.sh, start.sh, stop.sh and reset_setup.sh source it, after they found
# their own directory (${_DIR}, the directory examples/encrypt/):
#
#   source "${_DIR}/env.sh"
#
# A variable which is already defined in the terminal wins: GITS_DEMO_SSH_KEY=... /bin/bash gits.sh diff
#

# Where everything generated goes: gits_source/, repoa/, repob/, tmp/, server.log.
# Here, next to the scripts. The test tests/test016 points it to its own directory.
export GITS_DEMO_WORK="${GITS_DEMO_WORK:-${_DIR}}"

# The keys, the sockets, the pid files.
GITS_DEMO_TMP="${GITS_DEMO_TMP:-${GITS_DEMO_WORK}/tmp}"

# The storage of the demo: a local git repository created by reset_setup.sh. gits reads it from
# GITS_SOURCE. Deliberately not "the one of the terminal wins": GITS_SOURCE of your terminal is
# your real storage, and the demo must never push there. To use another one: GITS_DEMO_SOURCE.
GITS_DEMO_SOURCE="${GITS_DEMO_SOURCE:-${GITS_DEMO_WORK}/gits_source}"
export GITS_SOURCE="${GITS_DEMO_SOURCE}"

# The second variable gits reads: the unix socket it sends encode / decode requests to.
# start.sh starts the server on it, stop.sh removes it. At most about 100 characters.
export GITS_ENCRYPTION_SOCKET="${GITS_ENCRYPTION_SOCKET:-${GITS_DEMO_TMP}/ssenc.sock}"

# The ssh key everything is encrypted with and which opens what is stored: the private key file,
# its public key is next to it (<file>.pub). Read only by start.sh (loads it into the agent) and
# server.ts. keys.sh creates two: "key" and "key2". A name without a directory is a file in
# ${GITS_DEMO_TMP}: GITS_DEMO_SSH_KEY=key2 /bin/bash gits.sh diff
GITS_DEMO_SSH_KEY="${GITS_DEMO_SSH_KEY:-key}"
if [[ "${GITS_DEMO_SSH_KEY}" != */* ]]; then
  GITS_DEMO_SSH_KEY="${GITS_DEMO_TMP}/${GITS_DEMO_SSH_KEY}"
fi
export GITS_DEMO_SSH_KEY

# Only for "gits crypt rekey": the key the stored files get in place of GITS_DEMO_SSH_KEY.
# Not defined (the default): the server refuses rekey requests.
#   GITS_DEMO_NEW_SSH_KEY=key2 /bin/bash gits.sh crypt rekey --storage --yes
if [[ -n "${GITS_DEMO_NEW_SSH_KEY}" && "${GITS_DEMO_NEW_SSH_KEY}" != */* ]]; then
  GITS_DEMO_NEW_SSH_KEY="${GITS_DEMO_TMP}/${GITS_DEMO_NEW_SSH_KEY}"
fi
export GITS_DEMO_NEW_SSH_KEY

# Socket of the ssh-agent which start.sh starts only for the demo: the key above is loaded into
# this one, never into your own agent.
GITS_DEMO_AGENT="${GITS_DEMO_AGENT:-${GITS_DEMO_TMP}/agent.sock}"

# Log of the server: one line per file, "encrypted <file> -> <file>" or "decrypted <file> -> <file>".
# Defined as an empty text (GITS_DEMO_LOG=""): nothing is logged.
GITS_DEMO_LOG="${GITS_DEMO_LOG-${GITS_DEMO_WORK}/server.log}"

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
