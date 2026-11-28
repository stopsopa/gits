#
# Tells gits whether a file is an encoded one of the demo examples/base64_md5/ENCRYPT_PROCESS.md.
#
# gits calls it (env var GITS_ENCRYPTION_DETECT, see env.sh) for a file of the storage, in place
# of its built-in rule which knows only the files of https://github.com/stopsopa/encrypt:
#
#   /bin/bash examples/base64_md5/detect.sh <file>
#
#   exit code 0   the file is an encoded one. One line is printed: "md5:<checksum>",
#                 "gits crypt status" shows it in [...]
#   exit code 1   it is not (also: no such file)
#   exit code 2   wrong use (no argument)
#
# The format (server.ts writes it): one line,
#
#   <md5 of the base64 text, 32 hex characters>:<base64 of the content of the file>
#
# A file is an encoded one when it has exactly that shape AND the md5 of what is after the colon
# is what stands before it. A plain file which only looks similar doesn't pass the second check.
#
# By hand:
#
#   /bin/bash examples/base64_md5/detect.sh "examples/base64_md5/gits_source/git@github.com:demo__repoa.git/.env"; echo "exit code $?"
#

if [[ -z "${1}" ]]; then
  echo "${0} error: no file given, usage: /bin/bash ${0} <file>" >&2
  exit 2
fi

if [[ ! -f "${1}" ]]; then
  exit 1
fi

# one line only: more than one, or a file without the end of line after it, is not ours
if [[ "$(wc -l < "${1}" | tr -d " ")" != "1" ]]; then
  exit 1
fi

IFS= read -r LINE < "${1}"

if [[ ! "${LINE}" =~ ^([0-9a-f]{32}):([A-Za-z0-9+/]*=*)$ ]]; then
  exit 1
fi

STATED="${BASH_REMATCH[1]}"
DATA="${BASH_REMATCH[2]}"

# md5 of the base64 text: md5sum on Linux, md5 on macOS
if command -v md5sum > /dev/null; then
  REAL="$(printf "%s" "${DATA}" | md5sum | cut -d " " -f 1)"
else
  REAL="$(printf "%s" "${DATA}" | md5 -q)"
fi

if [[ "${STATED}" != "${REAL}" ]]; then
  exit 1
fi

echo "md5:${STATED}"
