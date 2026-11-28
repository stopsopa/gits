#
# Brings the demo examples/base64_md5/ENCRYPT_PROCESS.md to its state 0. Everything the demo
# generated is removed and created again:
#
#   gits_source/         the storage (GITS_SOURCE of the demo, see env.sh): an empty local git repository
#   GITS_PULL_TO_SYNC/   the clone of the storage gits keeps between its commands: removed
#   repoa/               a project: git repository with one commit, .git/gits.sh created by "gits init",
#   repob/               its git-ignored files registered with "gits add" (some of them as ":e:")
#   tmp/                 removed (socket and pid file of the server)
#   server.log           removed
#
# Nothing is pushed to the storage: that is where you start playing.
#
#   /bin/bash examples/base64_md5/reset_setup.sh        (from any directory)
#
# Removes without asking, but only the directories listed above, all inside examples/base64_md5.
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

# everything generated is here (examples/base64_md5, unless GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES says something else)
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
# Without the socket: init and add encode nothing, so no server is needed here
function gits {
  local NAME="${1}"
  shift
  (cd "${W}/${NAME}" && GITS_ENCRYPTION_SOCKET= /bin/bash "${_DIR}/gits.sh" "${@}") || fail "gits ${*} failed in >${NAME}<"
}

# --- state 0: nothing running, nothing generated

/bin/bash "${_DIR}/stop.sh"
mkdir -p "${W}" || fail "can't create directory GITS_MAIN_ENCRYPT_DIRECTORY_WHERE_ALL_LIVES=>${W}<"
rm -rf "${W:?}/tmp" "${W:?}/server.log"

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
Not in git (kept by gits): .env (encoded), config/local.json
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
Not in git (kept by gits): .env.local, secrets/token.txt, secrets/cert.bin (all three encoded), notes.txt
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

# a binary file: base64 takes any bytes
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
