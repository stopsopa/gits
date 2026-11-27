#
# Brings the demo examples/encrypt/ENCRYPT_PROCESS.md to its state 0. Everything the demo
# generated is removed and created again:
#
#   gits_source/   the storage (GITS_SOURCE of the demo, see env.sh): an empty local git repository
#   repoa/         a project: git repository with one commit, .git/gits.sh created by "gits init",
#   repob/         its git-ignored files registered with "gits add" (some of them encrypted)
#   tmp/           two new ssh keys: key (the one in use) and key2 (keys.sh)
#   server.log     removed
#   server.js      built again from server.ts, and bin/ssenc (the binary which encrypts) copied
#                  again from the checkout of the encrypt repository (encrypt.sh)
#
# Nothing is pushed to the storage: that is where you start playing.
#
#   /bin/bash examples/encrypt/reset_setup.sh        (from any directory)
#
# Removes without asking, but only the directories listed above, all inside examples/encrypt.
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

# everything generated is here (examples/encrypt, unless GITS_DEMO_WORK says something else)
W="${GITS_DEMO_WORK}"

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

# ${1} project, the rest: arguments of gits, started in the root of the project through the wrapper
function gits {
  local NAME="${1}"
  shift
  (cd "${W}/${NAME}" && /bin/bash "${_DIR}/gits.sh" "${@}") || fail "gits ${*} failed in >${NAME}<"
}

# --- state 0: nothing running, nothing generated

/bin/bash "${_DIR}/stop.sh"
mkdir -p "${W}" || fail "can't create directory GITS_DEMO_WORK=>${W}<"
rm -rf "${GITS_DEMO_TMP:?}" "${W:?}/server.log"

/bin/bash "${_DIR}/keys.sh" || fail "keys.sh failed"

# --- the server: the binary which encrypts copied to bin/, server.js built

/bin/bash "${_DIR}/encrypt.sh" || fail "encrypt.sh failed"

# --- the storage. Not bare, so its files can be looked at: a push updates the files too

rm -rf "${GITS_DEMO_SOURCE:?}"
g init -q "${GITS_DEMO_SOURCE}" || fail "git init failed, GITS_DEMO_SOURCE=>${GITS_DEMO_SOURCE}<"
g -C "${GITS_DEMO_SOURCE}" config receive.denyCurrentBranch updateInstead

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
  ${W}/repoa         cat repoa/.git/gits.sh
  ${W}/repob         cat repob/.git/gits.sh

Nothing is pushed yet. Next:

  cd "${W}"
  /bin/bash "${_DIR}/gits.sh" state

EEE
