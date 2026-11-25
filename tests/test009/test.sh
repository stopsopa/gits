#
# What is tested here: "gits --update", the binary replacing itself with a release.
#
# Nothing is downloaded from github. Releases are faked in a local directory (GITS_RELEASES),
# with the same layout github has:
#   <dir>/latest                    tag of the latest release (github: redirect)
#   <dir>/download/<tag>/<file>     the binary of the platform and SHA256SUMS.txt
#
# In this order:
#
#   1. the binary from compile.sh (version "dev") refuses to update; unknown argument prints the usage.
#   2. binaries with real versions v9.9.8 and v9.9.9 are compiled and put into the faked releases,
#      v9.9.8 is "installed" in ${WORK}/installed and started through a symlink.
#   3. --update --check: only says what is installed and what is the latest.
#   4. nothing is replaced without a "yes": no terminal to ask on, and the answer "n".
#   5. releases which are not what they should be, each one refused: checksum doesn't match,
#      the binary reports another version, the file is not a program, no checksum for this platform,
#      a tag which doesn't exist, no releases at all.
#   6. the update confirmed with "y": v9.9.8 -> v9.9.9. Then "up to date".
#   7. an older release on request (--update v9.9.8), without asking (GITS_CONFIRM=false).
#   8. a directory which is not writable: explained, nothing changed.
#
# After every step function "installed" checks which binary is installed: after every failure it has
# to be byte for byte the one which was there before, with no other file left next to it.
#
# /bin/bash tests/test009/test.sh
#
# Needs: cargo. Slow: gits is compiled three times here (versions v9.9.8, v9.9.9 and "dev" again at
# the end, so that the binary in the repository is the one the other tests expect).
# Skipped (exit code 0) on a platform for which no binaries are released.
#
# Checks are done with function "test" of bash/test.sh, see tests/_lib.sh
#

# where this file is (works in bash, zsh and sh): ${_DIR} is the directory of this test
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

# the common setup of all tests: ${WORK} (tmp/ next to this file, from now on also the current
# directory), own HOME and git config, function "test" and the helpers used inside of COMMAND
# (gits = the binary from compile.sh, has, listing, fail). Also ${TARGET} (rust target of this
# machine), ${_ROOT} and ${REAL_HOME} used below.
source "${_DIR}/../_lib.sh"

# the setup defined the storage, and --update needs nothing of it: it has to work without
# GITSTORAGESOURCE, like --help and --version
unset GITSTORAGESOURCE

# name of the file of a release for this machine, the same names gits looks for (src/update.rs)
# and the release workflow publishes. On any other platform there is nothing to update to: the test
# ends here as passed.
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

# the binary from compile.sh has version "dev": it is not a release, so it can't know whether a
# release is newer. It refuses and says why, exit code 1. GITS_CONFIRM=false: no question would be
# asked, the refusal comes before that. GITS_RELEASES points to a directory which doesn't exist yet,
# it is not even looked at.
COMMAND='GITS_RELEASES="${WORK}/releases" GITS_CONFIRM=false gits --update 2>&1 | has "this binary is a local build (version dev)"'
EXPECTED_STDOUT="this binary is a local build (version dev)"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "dev build refuses"

# --update takes "--check" or a tag, "--what" is neither: the usage is printed (the fragment is
# one line of it) and the exit code is 1
COMMAND='gits --update --what 2>&1 | has "gits --update --check"'
EXPECTED_STDOUT="gits --update --check"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "unknown argument: usage"

# ---------- binaries with real versions are needed for everything else ----------

# build_version <version> <output>
# compiles gits with the given version built in (env var GITS_VERSION is read by build.rs) and
# copies the result to <output>.
# - HOME is the real one for cargo: it keeps its toolchain and cache there
# - with ${TARGET} the result is in target/<target>/release, without it in target/release
# - the output of cargo is shown only when the build failed
# - the copy is started with --version: it has to report exactly the version asked for,
#   otherwise the rest of the test would test nothing
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

# sha256 of a file in the format of SHA256SUMS.txt ("<hash>  <name>"): sha256sum on Linux,
# shasum on macOS
function sha256 {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "${@}"
  else
    shasum -a 256 "${@}"
  fi
}

# release <directory of releases> <tag> <binary>
# puts <binary> into the faked releases as the file of this platform of release <tag>, and
# writes SHA256SUMS.txt with its checksum next to it (cd: the name in it has to be without a directory)
function release {
  local TARGET_DIR="${1}/download/${2}"
  mkdir -p "${TARGET_DIR}"
  cp "${3}" "${TARGET_DIR}/${ASSET}"
  (cd "${TARGET_DIR}" && sha256 "${ASSET}" > SHA256SUMS.txt)
}

# the two versions the test plays with: 9.9.8 will be the installed one, 9.9.9 the newer one
build_version v9.9.8 "${WORK}/bin-v9.9.8"
build_version v9.9.9 "${WORK}/bin-v9.9.9"

# the faked releases: both versions published, and "latest" says v9.9.9
REL="${WORK}/releases"
release "${REL}" v9.9.8 "${WORK}/bin-v9.9.8"
release "${REL}" v9.9.9 "${WORK}/bin-v9.9.9"
echo "v9.9.9" > "${REL}/latest"

# v9.9.8 "installed" in its own directory, with mode 755 like a real one, and reachable through
# a symlink in another directory (the way a binary in ~/bin often is). --update has to replace the
# real file and leave the link alone. ${GITS} is what the checks below start.
mkdir "${WORK}/installed" "${WORK}/path"
INSTALLED="${WORK}/installed/gits"
cp "${REL}/download/v9.9.8/${ASSET}" "${INSTALLED}"
chmod 755 "${INSTALLED}"
ln -s "${INSTALLED}" "${WORK}/path/gits"
GITS="${WORK}/path/gits"

# from now on every --update of this test reads the faked releases (single checks below
# override it with their own broken copy)
export GITS_RELEASES="${REL}"

# installed <tag> <label>
# sets COMMAND and calls "test", so it is one more check wherever it is called. The command:
#   cmp       the installed file is byte for byte the binary of release <tag> (prints nothing when equal)
#   listing   the directory has only "gits" in it: no downloaded file, no backup copy left behind
#   [[ -L ]]  what is in PATH is still a symlink, it was not replaced by a file
#   --version started through the symlink it runs and reports <tag>
# Each step runs only when the previous one passed (&&), so the expected output is the two lines
# "gits" (the listing) and "gits <tag>", with exit code 0.
function installed {
  EXPECTED_TAG="${1}"
  # ${EXPECTED_TAG} (not ${1}): COMMAND is executed later, by "test", where ${1} is something else
  COMMAND='cmp "${INSTALLED}" "${REL}/download/${EXPECTED_TAG}/${ASSET}" && listing "${WORK}/installed" && [[ -L "${GITS}" ]] && "${GITS}" --version'
  EXPECTED_STDOUT="gits
gits ${1}"
  EXPECTED_STDERR=""
  EXPECTED_CODE="0"
  test "installed binary is ${1}: ${2}"
}

# the starting point: v9.9.8 is installed
installed v9.9.8 "before"

# ---------- --check: only information ----------

# --check only compares: the installed version (the binary knows its own), the latest one (from
# the file "latest" of the faked releases) and how to install it. The whole output is compared,
# exit code 0. It asks nothing and replaces nothing.
COMMAND='"${GITS}" --update --check 2>&1'
EXPECTED_STDOUT="installed: v9.9.8
latest: v9.9.9
to install it: gits --update"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "--update --check"

# --check replaced nothing: still v9.9.8
installed v9.9.8 "after --check"

# ---------- nothing is changed when the answer is not yes ----------

# --update without GITS_CONFIRM=false asks "replace?" and waits for an answer. Here stdin is
# /dev/null and the output is a pipe: there is nobody to answer. It must not hang and must not
# assume "yes": it says how to run it without the question and ends with 1.
COMMAND='"${GITS}" --update 2>&1 < /dev/null | has "needs confirmation and there is no terminal, use GITS_CONFIRM=false"'
EXPECTED_STDOUT="needs confirmation and there is no terminal, use GITS_CONFIRM=false"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no terminal"

# nothing was replaced: still v9.9.8
installed v9.9.8 "after no terminal"

# what is shown before the question: the list of files which will be replaced. It has to be the
# real file (${WORK}/installed/gits), not the symlink gits was started through.
F1="files to replace:
  ${INSTALLED}"

# GITS_TEST_ANSWER="n" is the answer to the question (a variable only for tests, in place of
# typing). "No" is not an error: "nothing changed", exit code 0.
COMMAND='GITS_TEST_ANSWER="n" "${GITS}" --update 2>&1 | has "${F1}" "nothing changed"'
EXPECTED_STDOUT="${F1}
nothing changed"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "answer no: the real file is named, not the symlink"

# the answer was no: still v9.9.8
installed v9.9.8 "after answer no"

# ---------- releases which are not what they should be ----------

# a copy of the releases where the binary of v9.9.9 got one more byte after its checksum was
# written: what a broken download looks like
BAD="${WORK}/releases-bad-checksum"
cp -R "${REL}" "${BAD}"
echo "x" >> "${BAD}/download/v9.9.9/${ASSET}"

# the sha256 of the downloaded file is compared with SHA256SUMS.txt of the same release before
# anything else is done with it: it doesn't match, exit code 1
COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "checksum of downloaded >${ASSET}< doesn'"'"'t match SHA256SUMS.txt"'
EXPECTED_STDOUT="checksum of downloaded >${ASSET}< doesn't match SHA256SUMS.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "broken download"

# the broken download was removed, the installed binary was not touched: still v9.9.8
installed v9.9.8 "after broken download"

# a copy of the releases where release v9.9.9 holds the binary of v9.9.8, with a checksum
# which is right for that file
BAD="${WORK}/releases-bad-version"
cp -R "${REL}" "${BAD}"
release "${BAD}" v9.9.9 "${WORK}/bin-v9.9.8"

# the checksum passes ("checksum ok"), so the next check has to catch it: the downloaded binary
# is started with --version before it replaces anything, and it reports v9.9.8 instead of v9.9.9.
# Refused, exit code 1.
COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "checksum ok: ${ASSET}" "downloaded binary doesn'"'"'t work here, nothing was changed"'
EXPECTED_STDOUT="checksum ok: ${ASSET}
downloaded binary doesn't work here, nothing was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "binary of another version: checksum passed, caught by running it"

# the wrong binary did not replace the installed one: still v9.9.8 (the same version, but
# "installed" also checks that no file was left next to it)
installed v9.9.8 "after binary of another version"

# a copy of the releases where the file of v9.9.9 is a text file, again with a right checksum
BAD="${WORK}/releases-not-a-binary"
cp -R "${REL}" "${BAD}"
echo "not a program" > "${WORK}/garbage"
release "${BAD}" v9.9.9 "${WORK}/garbage"

# the checksum passes, starting the file fails (it is not a program): the same refusal as
# above, exit code 1. This is what a binary for another platform would look like too.
COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "downloaded binary doesn'"'"'t work here, nothing was changed"'
EXPECTED_STDOUT="downloaded binary doesn't work here, nothing was changed"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "not a binary"

# still v9.9.8
installed v9.9.8 "after not a binary"

# a copy of the releases where SHA256SUMS.txt of v9.9.9 has a line only for some other file
# (64 times "a" is a hash of the right length), nothing for the file of this platform
BAD="${WORK}/releases-no-sum"
cp -R "${REL}" "${BAD}"
echo "$(printf 'a%.0s' $(seq 1 64))  some-other-file" > "${BAD}/download/v9.9.9/SHA256SUMS.txt"

# without a checksum for the file it downloads gits doesn't continue: there is no "skip the
# verification". Exit code 1.
COMMAND='GITS_RELEASES="${BAD}" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "there is no checksum of >${ASSET}< in SHA256SUMS.txt"'
EXPECTED_STDOUT="there is no checksum of >${ASSET}< in SHA256SUMS.txt"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no checksum"

# still v9.9.8
installed v9.9.8 "after no checksum"

# a tag given by hand which is not in the releases: the files of it can't be fetched.
# gits asks whether such a release exists and ends with 1.
COMMAND='GITS_CONFIRM=false "${GITS}" --update v1.2.3 2>&1 | has "is >v1.2.3< a published release with all files?"'
EXPECTED_STDOUT="is >v1.2.3< a published release with all files?"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "release which doesn't exist"

# still v9.9.8
installed v9.9.8 "after release which doesn't exist"

# GITS_RELEASES pointing to a directory which doesn't exist: there is no "latest" to read, so
# gits can't even say which version would be installed. Exit code 1.
COMMAND='GITS_RELEASES="${WORK}/no-releases" GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "can'"'"'t find out the latest release"'
EXPECTED_STDOUT="can't find out the latest release"
EXPECTED_STDERR=""
EXPECTED_CODE="1"
test "no release at all"

# still v9.9.8
installed v9.9.8 "after no release at all"

# ---------- the update, confirmed ----------

# the real thing: the good releases and the answer "y". The three lines which matter:
#   - the downloaded binary was started and reports v9.9.9 (before the replacing)
#   - the installed binary was started and reports v9.9.9 (after the replacing)
#   - the summary, from which version to which
# Exit code 0.
COMMAND='GITS_TEST_ANSWER="y" "${GITS}" --update 2>&1 | has "test ok: downloaded binary reports gits v9.9.9" "test ok: installed binary reports gits v9.9.9" "gits updated: v9.9.8 -> v9.9.9"'
EXPECTED_STDOUT="test ok: downloaded binary reports gits v9.9.9
test ok: installed binary reports gits v9.9.9
gits updated: v9.9.8 -> v9.9.9"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "update: tested before and after replacing"

# now the installed file is the binary of v9.9.9, nothing else is next to it and the symlink
# is still a symlink
installed v9.9.9 "after update"

# --update again: installed and latest are the same, so there is nothing to ask and nothing to
# do. The whole output is compared, exit code 0.
COMMAND='"${GITS}" --update 2>&1'
EXPECTED_STDOUT="installed: v9.9.9
latest: v9.9.9
gits is up to date"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "up to date: nothing to do"

# still v9.9.9, untouched
installed v9.9.9 "after up to date"

# ---------- an older release, on request ----------

# a tag given by hand is installed whatever is installed now, also an older one: v9.9.8 over
# v9.9.9. GITS_CONFIRM=false: no question. Exit code 0.
COMMAND='GITS_CONFIRM=false "${GITS}" --update v9.9.8 2>&1 | has "requested: v9.9.8" "gits updated: v9.9.9 -> v9.9.8"'
EXPECTED_STDOUT="requested: v9.9.8
gits updated: v9.9.9 -> v9.9.8"
EXPECTED_STDERR=""
EXPECTED_CODE="0"
test "older release"

# back on v9.9.8
installed v9.9.8 "after older release"

# ---------- a directory which is not writable: nothing can be put next to the binary, nothing is changed ----------

# root can write everywhere, chmod would not stop it: this part is skipped for root
if [[ "$(id -u)" != "0" ]]; then
  # the directory of the installed binary becomes read only: the new binary can't be downloaded
  # next to the installed one and the installed one can't be replaced
  chmod 555 "${WORK}/installed"

  # gits finds that out before downloading anything and says what is needed. Exit code 1.
  COMMAND='GITS_CONFIRM=false "${GITS}" --update 2>&1 | has "the directory has to be writable for the update"'
  EXPECTED_STDOUT="the directory has to be writable for the update"
  EXPECTED_STDERR=""
  EXPECTED_CODE="1"
  test "directory not writable"

  # writable again: the next check lists the directory, and the next run of the test has to be
  # able to remove it
  chmod 755 "${WORK}/installed"

  # nothing was changed and nothing was left in the directory: still v9.9.8
  installed v9.9.8 "after directory not writable"
fi

# the builds above went into target/ of the repository and the last one left there is v9.9.9.
# One more build with version "dev" puts back what compile.sh makes, for whatever is built or
# tested after this test. (The copy in ${WORK}/bin-dev is not used, build_version only checks
# with it that the build really reports "gits dev".)
build_version dev "${WORK}/bin-dev"
