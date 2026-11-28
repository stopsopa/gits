#
# Brings the demo examples/encrypt_os_ssh_agent/ENCRYPT_PROCESS.md to its state 0. Everything the demo
# generated is removed and created again:
#
#   gits_source/   the storage (GITS_SOURCE of the demo, see env.sh): an empty local git repository
#   GITS_PULL_TO_SYNC/   the clone of the storage gits keeps between its commands: removed
#   repoa/         a project: git repository with one commit, .git/gits.sh created by "gits init",
#   repob/         its git-ignored files registered with "gits add" (some of them encrypted)
#   tmp/           removed (socket and pid file of the server)
#   server.log     removed
#   keys/          the two ssh keys, key (the one in use) and key2: the files are kept (created
#                  only when missing, keys.sh), but EVERY KEY WITH "gits" IN ITS LABEL IS REMOVED
#                  FROM YOUR SSH-AGENT (ssh-add -d): the two of this demo (gits-os-agent-demo-...)
#                  and any other one, also a key of yours which has "gits" in its comment or,
#                  when it has no comment, in the path it was loaded from. State 0 is "the keys exist, nobody loaded
#                  them": loading is a step of the guide. Nothing else in the agent is touched
#   server.js      built again from server.ts, and bin/ssenc (the binary which encrypts) copied
#                  again from the checkout of the encrypt repository (encrypt.sh)
#
# Nothing is pushed to the storage: that is where you start playing.
#
# It needs no key in the ssh-agent ("gits init" and "gits add" encrypt nothing, the wrapper is
# called without the socket). At its end it prints the ssh-add command which loads the keys.
#
#   /bin/bash examples/encrypt_os_ssh_agent/reset_setup.sh        (from any directory)
#
# Removes without asking, but only the directories listed above, all inside examples/encrypt_os_ssh_agent.
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

source "${_DIR}/env.sh"

# everything generated is here (examples/encrypt_os_ssh_agent, unless GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES says something else)
W="${GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES}"

GREEN=$'\033[32m'
RESET=$'\033[0m'

function fail {
  echo "${0} error: ${1}"
  exit 1
}

# git of the demo repositories: doesn't depend on your git config
function g {
  git -c user.name="gits demo" -c user.email="demo@example.com" "${@}"
}

# Creates one project: ${1} name of the directory. Files are created by the caller before commit.
function repo {
  local NAME="${1}"
  rm -rf "${W:?}/${NAME}"
  mkdir -p "${W}/${NAME}" || fail "can't create directory >${W}/${NAME}<"
  g init -q "${W}/${NAME}" || fail "git init failed in >${W}/${NAME}<"
  # never fetched or pushed: gits only takes the name of the directory in the storage from it
  g -C "${W}/${NAME}" remote add origin "git@github.com:demo/${NAME}.git"
}

function commit {
  local NAME="${1}"
  g -C "${W}/${NAME}" add -A || fail "git add failed in >${NAME}<"
  g -C "${W}/${NAME}" commit -q -m "first commit" || fail "git commit failed in >${NAME}<"
}

# ${1} project, the rest: arguments of gits, started in the root of the project through the wrapper.
# Without the socket: init and add encrypt nothing, so no server and no loaded key is needed here
function gits {
  local NAME="${1}"
  shift
  (cd "${W}/${NAME}" && GITS_ENCRYPTION_SOCKET= /bin/bash "${_DIR}/gits.sh" "${@}") || fail "gits ${*} failed in >${NAME}<"
}

# --- state 0: nothing running, nothing generated

/bin/bash "${_DIR}/stop.sh"
mkdir -p "${W}" || fail "can't create directory GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES=>${W}<"
rm -rf "${W:?}/tmp" "${W:?}/server.log"

# Every key which has "gits" in its label out of the agent of this terminal. The label (the
# comment) is the last column of "ssh-add -l": "gits-os-agent-demo-key" for the keys of this
# demo, and e.g. "gits-demo-key", "gits-encryption" for keys from other attempts.
# ssh-add -L prints one line per loaded key: <type> <public key in base64> <label>. Only the
# label is looked at (the base64 part could contain "gits" by accident). ssh-add -d wants a
# public key file, so each such line is written to a temporary one.
# No agent, or no key in it: nothing happens.
UNLOAD="$(mktemp)" || fail "mktemp failed"
while IFS= read -r LINE; do
  LABEL="$(echo "${LINE}" | cut -d " " -f 3-)"
  if [[ "${LABEL}" != *gits* ]]; then
    continue
  fi
  echo "${LINE}" > "${UNLOAD}"
  if ssh-add -q -d "${UNLOAD}" 2> /dev/null; then
    echo "removed from the ssh-agent: ${LABEL}"
  else
    echo "can't remove from the ssh-agent: ${LABEL}"
  fi
done <<< "$(ssh-add -L 2> /dev/null)"
rm -f "${UNLOAD}"

# creates only the keys which are missing; what it says about the agent is shown at the end
KEYS_OUTPUT="$(/bin/bash "${_DIR}/keys.sh")" || fail "keys.sh failed: ${KEYS_OUTPUT}"

# --- the server: the binary which encrypts copied to bin/, server.js built

/bin/bash "${_DIR}/encrypt.sh" || fail "encrypt.sh failed"

# --- the storage. Not bare, so its files can be looked at: a push updates the files too

# the kept clone of the old storage goes with it: the new storage has another history
rm -rf "${GITS_SOURCE:?}" "${GITS_PULL_TO_SYNC:?}"
g init -q "${GITS_SOURCE}" || fail "git init failed, GITS_SOURCE=>${GITS_SOURCE}<"
g -C "${GITS_SOURCE}" config receive.denyCurrentBranch updateInstead

# --- repoa: .env and config/local.json are ignored by git

repo repoa
mkdir -p "${W}/repoa/src" "${W}/repoa/config"

cat <<'EEE' > "${W}/repoa/README.md"
# repoa

In git: README.md, src/app.js, config/default.json, .gitignore
Not in git (kept by gits): .env (encrypted), config/local.json
EEE

cat <<'EEE' > "${W}/repoa/src/app.js"
console.log(`api key: ${process.env.API_KEY}`);
EEE

cat <<'EEE' > "${W}/repoa/config/default.json"
{ "port": 3000 }
EEE

cat <<'EEE' > "${W}/repoa/.gitignore"
.env
config/local.json
EEE

cat <<'EEE' > "${W}/repoa/.env"
API_KEY=repoa-abc123
DB_PASSWORD=repoa-secret
EEE

cat <<'EEE' > "${W}/repoa/config/local.json"
{ "port": 3001, "debug": true }
EEE

commit repoa

# --- repob: .env.local, secrets/ and notes.txt are ignored by git

repo repob
mkdir -p "${W}/repob/secrets"

cat <<'EEE' > "${W}/repob/README.md"
# repob

In git: README.md, main.sh, .gitignore
Not in git (kept by gits): .env.local, secrets/token.txt, secrets/cert.bin (all three encrypted), notes.txt
EEE

cat <<'EEE' > "${W}/repob/main.sh"
echo "token: $(cat secrets/token.txt)"
EEE

cat <<'EEE' > "${W}/repob/.gitignore"
.env.local
secrets/
notes.txt
EEE

cat <<'EEE' > "${W}/repob/.env.local"
STRIPE_KEY=repob-sk_test_123
EEE

cat <<'EEE' > "${W}/repob/secrets/token.txt"
repob-token-456
EEE

# a binary file: ssenc stores it in its "blob" mode (the server asks for --mode auto)
head -c 256 /dev/urandom > "${W}/repob/secrets/cert.bin"

cat <<'EEE' > "${W}/repob/notes.txt"
local notes of repob, not a secret, just not for git
EEE

commit repob

# --- gits: the config of each project, then its ignored files. Paths through stdin: no questions

gits repoa init
printf ".env\n" | gits repoa add -e
printf "config/local.json\n" | gits repoa add

gits repob init
printf ".env.local\nsecrets/token.txt\nsecrets/cert.bin\n" | gits repob add -e
printf "notes.txt\n" | gits repob add

cat <<EEE
${GREEN}
state 0 is ready:${RESET}

  ${W}/gits_source   the storage (empty)
  ${W}/keys          key, key2 (and .pub)
  ${W}/repoa         cat repoa/.git/gits.sh
  ${W}/repob         cat repob/.git/gits.sh

Nothing is pushed yet.

${KEYS_OUTPUT}

Next:

  cd "${W}"
  /bin/bash "${_DIR}/gits.sh" state

EEE
