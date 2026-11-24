#!/usr/bin/env bash

# Test fixture for lib/cli.test.ts - simulates a slow program.
#
# Steps:
#   1. prints N lines to stdout (outN) and stderr (errN), waiting DELAY seconds between them
#   2. prints value of env var CLI_FIXTURE_VAR as "env:<value>"
#   3. prints its working directory as "pwd:<dir>"
#   4. exits with given exit code
#
# Arguments (all optional):
#   $1 - number of lines        (default 3)
#   $2 - delay in seconds       (default 0.2, fractions allowed)
#   $3 - exit code              (default 0)
#
# Examples:
#   bash lib/cli.fixtures/emit.sh
#     # out1..out3 + err1..err3, 0.2s apart, env:, pwd:<current dir>, exit 0
#
#   CLI_FIXTURE_VAR=hello bash lib/cli.fixtures/emit.sh 2 0.5 7
#     # out1, out2 (0.5s apart), env:hello, pwd:<current dir>, exit 7

set -euo pipefail

LINES_COUNT="${1:-3}"
DELAY="${2:-0.2}"
EXIT_CODE="${3:-0}"

for (( i = 1; i <= LINES_COUNT; i++ )); do
  echo "out${i}"
  echo "err${i}" >&2

  if (( i < LINES_COUNT )); then
    sleep "${DELAY}"
  fi
done

echo "env:${CLI_FIXTURE_VAR:-}"
echo "pwd:$(pwd -P)"

exit "${EXIT_CODE}"
