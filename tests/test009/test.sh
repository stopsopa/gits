#
# gits --update: the binary replaces itself with a release.
# Releases are faked in a local directory (GITS_RELEASES), with the same layout github has:
#   <dir>/latest                    tag of the latest release (github: redirect)
#   <dir>/download/<tag>/<file>
#
# /bin/bash tests/test009/test.sh
# /bin/bash test.sh test009
#
# Slow: gits is compiled three times here (versions v9.9.8, v9.9.9 and "dev" again at the end).
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

# --update needs nothing of the storage
unset GITSTORAGESOURCE

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) ASSET="gits-darwin-arm64" ;;
  Linux-x86_64) ASSET="gits-linux-x64" ;;
  Linux-aarch64 | Linux-arm64) ASSET="gits-linux-arm64" ;;
  *)
    echo "skipped: no released binaries for $(uname -s)-$(uname -m)"
    exit 0
    ;;
esac

# ---------- a local build (version "dev") refuses to update ----------

COMMAND='GITS_RELEASES="${WORK}/releases" GITS_CONFIRM=false gits --update 2>&1 | has "this binary is a local build (version dev)"'
EXPECTED_STDOUT="this binary is a local build (version dev)"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "dev build refuses"

COMMAND='gits --update --what 2>&1 | has "gits --update --check"'
EXPECTED_STDOUT="gits --update --check"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unknown argument: usage"

# ---------- binaries with real versions are needed for everything else ----------

# build_version <version> <output>
function build_version {
  local BUILT="${_ROOT}/target/release/gits"
  if [[ -n "${TARGET}" ]]; then
    GITS_VERSION="${1}" HOME="${REAL_HOME}" cargo build --release --target "${TARGET}" --manifest-path "${_ROOT}/Cargo.toml" > "${WORK}/cargo.log" 2>&1
    BUILT="${_ROOT}/target/${TARGET}/release/gits"
  else
    GITS_VERSION="${1}" HOME="${REAL_HOME}" cargo build --release --manifest-path "${_ROOT}/Cargo.toml" > "${WORK}/cargo.log" 2>&1
  fi
  if [[ "${?}" != "0" ]]; then
    cat "${WORK}/cargo.log"
    fail "cargo build of version >${1}< failed"
  fi
  cp "${BUILT}" "${2}"
  if [[ "$("${2}" --version)" != "gits ${1}" ]]; then
    fail "binary built for the test reports >$("${2}" --version)< instead of >gits ${1}<"
  fi
}

function sha256 {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${@}"
  else
    shasum -a 256 "${@}"
  fi
}

# release <directory of releases> <tag> <binary>
function release {
  local TARGET_DIR="${1}/download/${2}"
  mkdir -p "${TARGET_DIR}"
  cp "${3}" "${TARGET_DIR}/${ASSET}"
  (cd "${TARGET_DIR}" && sha256 "${ASSET}" > SHA256SUMS.txt)
}

build_version v9.9.8 "${WORK}/bin-v9.9.8"
build_version v9.9.9 "${WORK}/bin-v9.9.9"

REL="${WORK}/releases"
release "${REL}" v9.9.8 "${WORK}/bin-v9.9.8"
release "${REL}" v9.9.9 "${WORK}/bin-v9.9.9"
echo "v9.9.9" > "${REL}/latest"

# installed: v9.9.8, started through a symlink (the real file has to be replaced, not the link)
mkdir "${WORK}/installed" "${WORK}/path"
INSTALLED="${WORK}/installed/gits"
cp "${REL}/download/v9.9.8/${ASSET}" "${INSTALLED}"
chmod 755 "${INSTALLED}"
ln -s "${INSTALLED}" "${WORK}/path/gits"
GITS="${WORK}/path/gits"

export GITS_RELEASES="${REL}"

# installed <tag> <label>
# the installed binary is the one from the release <tag>, no other files left next to it,
# the symlink is still a symlink, and it runs
function installed {
  EXPECTED_TAG="${1}"
  COMMAND='cmp "${INSTALLED}" "${REL}/download/${EXPECTED_TAG}/${ASSET}" && listing "${WORK}/installed" && [[ -L "${GITS}" ]] && "${GITS}" --version'
  EXPECTED_STDOUT="gits
gits ${1}"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "installed binary is ${1}: ${2}"
}

installed v9.9.8 "before"

# ---------- --check: only information ----------

COMMAND='"${GITS}" --update --check 2>&1'
EXPECTED_STDOUT="installed: v9.9.8
latest: v9.9.9
to install it: gits --update"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--update --check"

installed v9.9.8 "after --check"

# ---------- nothing is changed when the answer is not yes ----------

# no terminal and nothing says "don't ask": explained, not hanging
COMMAND='"${GITS}" --update 2>&1 < /dev/null | has "needs confirmation and there is no terminal, use GITS_CONFIRM=false"'
EXPECTED_STDOUT="needs confirmation and there is no terminal, use GITS_CONFIRM=false"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no terminal"

installed v9.9.8 "after no terminal"

F1="files to replace:
  ${INSTALLED}"

COMMAND='GITS_TEST_ANSWER="n" "${GITS}" --update 2>&1 | has "${F1}" "nothing changed"'
EXPECTED_STDOUT="${F1}
nothing changed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "answer no: the real file is named, not the symlink"

installed v9.9.8 "after answer no"

# ---------- releases which are not what they should be ----------

# broken download: checksum doesn't match
BAD="${WORK}/releases-bad-checksum"
cp -R "${REL}" "${BAD}"
echo "x" >> "${BAD}/download/v9.9.9/${ASSET}"

COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "checksum of downloaded >${ASSET}< doesn'"'"'t match SHA256SUMS.txt"'
EXPECTED_STDOUT="checksum of downloaded >${ASSET}< doesn't match SHA256SUMS.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "broken download"

installed v9.9.8 "after broken download"

# the checksum is fine but the binary is another version: caught by running it
BAD="${WORK}/releases-bad-version"
cp -R "${REL}" "${BAD}"
release "${BAD}" v9.9.9 "${WORK}/bin-v9.9.8"

COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "checksum ok: ${ASSET}" "downloaded binary doesn'"'"'t work here, nothing was changed"'
EXPECTED_STDOUT="checksum ok: ${ASSET}
downloaded binary doesn't work here, nothing was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "binary of another version: checksum passed, caught by running it"

installed v9.9.8 "after binary of another version"

# the checksum is fine but the file is not a program at all
BAD="${WORK}/releases-not-a-binary"
cp -R "${REL}" "${BAD}"
echo "not a program" > "${WORK}/garbage"
release "${BAD}" v9.9.9 "${WORK}/garbage"

COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "downloaded binary doesn'"'"'t work here, nothing was changed"'
EXPECTED_STDOUT="downloaded binary doesn't work here, nothing was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "not a binary"

installed v9.9.8 "after not a binary"

# no checksum for this platform: never "skip verification"
BAD="${WORK}/releases-no-sum"
cp -R "${REL}" "${BAD}"
echo "$(printf 'a%.0s' $(seq 1 64))  some-other-file" > "${BAD}/download/v9.9.9/SHA256SUMS.txt"

COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "there is no checksum of >${ASSET}< in SHA256SUMS.txt"'
EXPECTED_STDOUT="there is no checksum of >${ASSET}< in SHA256SUMS.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no checksum"

installed v9.9.8 "after no checksum"

COMMAND='GITS_CONFIRM=false "${GITS}" --update v1.2.3 2>&1 | has "is >v1.2.3< a published release with all files?"'
EXPECTED_STDOUT="is >v1.2.3< a published release with all files?"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "release which doesn't exist"

installed v9.9.8 "after release which doesn't exist"

COMMAND='GITS_RELEASES="${WORK}/no-releases" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "can'"'"'t find out the latest release"'
EXPECTED_STDOUT="can't find out the latest release"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no release at all"

installed v9.9.8 "after no release at all"

# ---------- the update, confirmed ----------

COMMAND='GITS_TEST_ANSWER="y" "${GITS}" --update 2>&1 | has "test ok: downloaded binary reports gits v9.9.9" "test ok: installed binary reports gits v9.9.9" "gits updated: v9.9.8 -> v9.9.9"'
EXPECTED_STDOUT="test ok: downloaded binary reports gits v9.9.9
test ok: installed binary reports gits v9.9.9
gits updated: v9.9.8 -> v9.9.9"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "update: tested before and after replacing"

installed v9.9.9 "after update"

COMMAND='"${GITS}" --update 2>&1'
EXPECTED_STDOUT="installed: v9.9.9
latest: v9.9.9
gits is up to date"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "up to date: nothing to do"

installed v9.9.9 "after up to date"

# ---------- an older release, on request ----------

COMMAND='GITS_CONFIRM=false "${GITS}" --update v9.9.8 2>&1 | has "requested: v9.9.8" "gits updated: v9.9.9 -> v9.9.8"'
EXPECTED_STDOUT="requested: v9.9.8
gits updated: v9.9.9 -> v9.9.8"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "older release"

installed v9.9.8 "after older release"

# ---------- a directory which is not writable: nothing can be put next to the binary, nothing is changed ----------

if [[ "$(id -u)" != "0" ]]; then
  chmod 555 "${WORK}/installed"

  COMMAND='GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "the directory has to be writable for the update"'
  EXPECTED_STDOUT="the directory has to be writable for the update"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "directory not writable"

  chmod 755 "${WORK}/installed"

  installed v9.9.8 "after directory not writable"
fi

# the binary in the repository is "dev" again for the tests which run after this one
build_version dev "${WORK}/bin-dev"
