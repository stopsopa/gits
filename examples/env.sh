#
# Every env var of the demo examples/ENCRYPT_PROCESS.md, in one place.
#
# Not called by itself: gits.sh, keys.sh, start.sh and stop.sh source it, after they found
# their own directory (${_DIR}, the directory examples/):
#
#   source "${_DIR}/env.sh"
#
# A variable which is already defined in the terminal wins: GITS_DEMO_SSH_KEY=... /bin/bash gits.sh diff
#

# Everything the demo generates (the key, the sockets, the pid files) is in examples/tmp.
GITS_DEMO_TMP="${GITS_DEMO_TMP:-${_DIR}/tmp}"

# The only variable here which gits reads: the unix socket it sends encode / decode requests to.
# start.sh starts the server on it, stop.sh removes it. At most about 100 characters.
export GITS_ENCRYPTION_SOCKET="${GITS_ENCRYPTION_SOCKET:-${GITS_DEMO_TMP}/ssenc.sock}"

# The ssh key everything is encrypted with: the private key file, its public key is next to it
# (<file>.pub). Read only by keys.sh (creates it), start.sh (loads it into the agent) and server.ts.
export GITS_DEMO_SSH_KEY="${GITS_DEMO_SSH_KEY:-${GITS_DEMO_TMP}/key}"

# Socket of the ssh-agent which start.sh starts only for the demo: the key above is loaded into
# this one, never into your own agent.
GITS_DEMO_AGENT="${GITS_DEMO_AGENT:-${GITS_DEMO_TMP}/agent.sock}"

# Log of the server: one line per file, "encrypted <file> -> <file>" or "decrypted <file> -> <file>".
# Defined as an empty text (GITS_DEMO_LOG=""): nothing is logged.
GITS_DEMO_LOG="${GITS_DEMO_LOG-${_DIR}/server.log}"

# Checkout of https://github.com/stopsopa/encrypt: server.ts takes encrypt() and decrypt() from it.
export GITS_DEMO_ENCRYPT="${GITS_DEMO_ENCRYPT:-${_DIR}/../__linked/STOPSOPA__encrypt/STOPSOPA__encrypt}"

# The gits binary which gits.sh starts: the one compiled here (/bin/bash compile.sh).
GITS_DEMO_BIN="${GITS_DEMO_BIN:-$(ls "${_DIR}"/../bin/*/gits 2> /dev/null | head -n 1)}"
