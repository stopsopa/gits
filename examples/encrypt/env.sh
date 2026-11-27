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

# Checkout of https://github.com/stopsopa/encrypt: server.ts takes encrypt() and decrypt() from it.
export GITS_DEMO_ENCRYPT="${GITS_DEMO_ENCRYPT:-${_DIR}/../../__linked/STOPSOPA__encrypt/STOPSOPA__encrypt}"

# The gits binary which gits.sh starts: the one compiled here (/bin/bash compile.sh).
GITS_DEMO_BIN="${GITS_DEMO_BIN:-$(ls "${_DIR}"/../../bin/*/gits 2> /dev/null | head -n 1)}"
