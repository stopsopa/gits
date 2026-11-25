# Body of the GitHub Release page (markdown), printed on stdout.
#
#   /bin/bash bash/release_notes.sh <tag> <owner/repository> [directory with release files]
#
# examples (from the root of the project):
#   /bin/bash bash/release_notes.sh v0.1.0 stopsopa/gits release-dist > release_notes.md
#   /bin/bash bash/release_notes.sh v0.1.0 stopsopa/gits       # without the table of checksums
#
# The body consists of:
#   1. section "## <tag>" of changelog.md (skipped when there is no such section)
#   2. how to update, then for each binary a block of commands: download + verify checksum
#      (hashes from <directory>/SHA256SUMS.txt, lines "<hash>  <file>"; without the directory
#      the blocks have no checksum part). The file lands in a new temporary directory
#      (the block starts with cd to it), README.md (1. Install -> Install) continues from there
#   3. table of checksums, only when the directory is given
#
# Used by .github/workflows/rust.yml (job release). To see the result before a release:
# xx "release notes preview" [tag]

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
_ROOT="$(cd "${_DIR}/.." && pwd)"

TAG="${1}"
REPOSITORY="${2}"
DIST="${3}"

if [[ -z "${TAG}" || -z "${REPOSITORY}" ]]; then
  echo "${0} error: usage: /bin/bash bash/release_notes.sh <tag> <owner/repository> [directory] - got TAG=>${TAG}< REPOSITORY=>${REPOSITORY}<" >&2
  exit 1
fi

if [[ -n "${DIST}" && ! -f "${DIST}/SHA256SUMS.txt" ]]; then
  echo "${0} error: file >${DIST}/SHA256SUMS.txt< doesn't exist" >&2
  exit 1
fi

BASE="https://github.com/${REPOSITORY}/releases/download/${TAG}"

# 1. everything between "## <tag>" and the next "## " heading
CHANGES=""
if [[ -f "${_ROOT}/changelog.md" ]]; then
  CHANGES="$(awk -v tag="${TAG}" '
    /^## / { found = ($2 == tag); next }
    found { print }
  ' "${_ROOT}/changelog.md")"
fi

if [[ -n "${CHANGES//[[:space:]]/}" ]]; then
  cat <<EEE
${CHANGES}

EEE
fi

cat <<EEE
### Update

\`\`\`sh
gits --update            # to the latest release
gits --update ${TAG}     # to this one
\`\`\`

### Installation & Checksum Verification

Pick the block of your platform. It creates a new temporary directory, downloads the binary there as \`gits\` and verifies its checksum. Stay in that directory (the same terminal) for the next step.
Then go back to [README.md → 1. Install → Install](https://github.com/${REPOSITORY}#install) to move it to its place and set up the shell.

EEE

# One block of commands for one binary. Without the hash (no directory given) the checksum part is skipped.
function block {
  local FILE="${1}"
  local HASH="${2}"
  local PLATFORM="${FILE}"

  case "${FILE}" in
    gits-darwin-arm64) PLATFORM="macOS, Apple Silicon" ;;
    gits-linux-x64) PLATFORM="Linux, x64" ;;
    gits-linux-arm64) PLATFORM="Linux, arm64" ;;
  esac

  cat <<EEE
#### ${PLATFORM}: \`${FILE}\`

\`\`\`bash
# New empty directory: the file is called gits, downloading it
# to a directory which already has a file with this name would overwrite it
cd "\$(mktemp -d)"

# Download via curl:
curl -fL -o gits \\
  ${BASE}/${FILE}

# Or download via wget:
wget -O gits \\
  ${BASE}/${FILE}
EEE

  if [[ -n "${HASH}" ]]; then
    cat <<EEE

# Verify checksum:
printf '%s\n' \\
  '${HASH}  gits' \\
  | shasum -a 256 -c -
# (on Linux without shasum replace "shasum -a 256 -c -" with "sha256sum -c -")
# expected output:
#   gits: OK
EEE
  fi

  cat <<EEE
\`\`\`

EEE
}

if [[ -n "${DIST}" ]]; then
  while read -r HASH FILE; do
    if [[ -n "${FILE}" ]]; then
      block "${FILE}" "${HASH}"
    fi
  done < "${DIST}/SHA256SUMS.txt"
else
  block "gits-darwin-arm64" ""
  block "gits-linux-x64" ""
  block "gits-linux-arm64" ""
fi

cat <<EEE
Checksums of all files are also in \`SHA256SUMS.txt\` (\`gits --update\` verifies them by itself).
EEE

if [[ -n "${DIST}" ]]; then
  cat <<EEE

### SHA-256 Checksums

| File | SHA-256 Checksum |
| --- | --- |
EEE

  while read -r HASH FILE; do
    if [[ -n "${FILE}" ]]; then
      echo "| \`${FILE}\` | \`${HASH}\` |"
    fi
  done < "${DIST}/SHA256SUMS.txt"
fi
