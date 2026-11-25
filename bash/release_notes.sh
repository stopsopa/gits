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
#   2. how to update and how to install
#   3. table of checksums from <directory>/SHA256SUMS.txt (lines "<hash>  <file>"),
#      only when the directory is given
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

### Install

Pick the binary of your platform:

| Platform | File |
| --- | --- |
| macOS, Apple Silicon | \`gits-darwin-arm64\` |
| Linux, x64 | \`gits-linux-x64\` |
| Linux, arm64 | \`gits-linux-arm64\` |

\`\`\`sh
mkdir -p ~/.gits
curl -fsSL "${BASE}/gits-darwin-arm64" -o ~/.gits/gits
chmod +x ~/.gits/gits

# ~/.zshrc or ~/.bashrc
export PATH="\${HOME}/.gits:\${PATH}"
export GITS_SOURCE="git@github.com:<owner>/<storage repository>.git"
\`\`\`

Checksums of all files are in \`SHA256SUMS.txt\` (\`gits --update\` verifies them by itself).
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
