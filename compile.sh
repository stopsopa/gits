# Builds the gits binary for the machine it is executed on.
#
#   /bin/bash compile.sh
#
# Result:
#   bin/<arch>/gits
#
# stdout: only the absolute path of the binary, so it can be consumed by other scripts:
#           GITS="$(/bin/bash compile.sh)"
# stderr: everything else (progress, errors)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${DIR}/bash/detect_arch.sh"

GREEN=$'\033[32m'
RESET=$'\033[0m'

echo "Building for target '${TARGET}' (arch: ${ARCH_DIR})..." >&2

# a local build never pretends to be a release ("gits --update" refuses to replace it)
export GITS_VERSION="dev"

if [[ -n "${TARGET}" ]]; then
  cargo build --release --target "${TARGET}" --manifest-path "${DIR}/Cargo.toml" >&2
  BUILD_STATUS=$?
else
  cargo build --release --manifest-path "${DIR}/Cargo.toml" >&2
  BUILD_STATUS=$?
fi

if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "${0} error: cargo build failed with exit code >${BUILD_STATUS}<" >&2
  exit "${BUILD_STATUS}"
fi

mkdir -p "${DIR}/bin/${ARCH_DIR}"

SRC_BIN="${DIR}/target/${TARGET}/release/gits"
if [[ ! -f "${SRC_BIN}" ]]; then
  SRC_BIN="${DIR}/target/release/gits"
fi

if [[ ! -f "${SRC_BIN}" ]]; then
  echo "${0} error: built binary not found at >${SRC_BIN}<" >&2
  exit 1
fi

cp "${SRC_BIN}" "${GITS_BIN_PATH}"

echo "${GREEN}Done. Binary:${RESET}" >&2

echo "${GITS_BIN_PATH}"
