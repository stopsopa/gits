# Body of the GitHub Release page, printed on stdout.
#
#   /bin/bash bash/release_notes.sh v0.1.0 stopsopa/gits > release_notes.md
#
# Used by .github/workflows/rust.yml (job release).

TAG="${1}"
REPOSITORY="${2}"

if [[ -z "${TAG}" || -z "${REPOSITORY}" ]]; then
  echo "${0} error: usage: /bin/bash bash/release_notes.sh <tag> <owner/repository>" >&2
  exit 1
fi

BASE="https://github.com/${REPOSITORY}/releases/download/${TAG}"

cat <<EEE
## Update

\`\`\`sh
gits --update            # to the latest release
gits --update ${TAG}     # to this one
\`\`\`

## Install

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
export GITSTORAGESOURCE="git@github.com:<owner>/<storage repository>.git"
\`\`\`

Checksums of all files are in \`SHA256SUMS.txt\`.
EEE
