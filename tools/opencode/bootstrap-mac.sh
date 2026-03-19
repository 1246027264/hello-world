#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SRC_DIR="${SCRIPT_DIR}/src"

OPENCODE_VERSION="${OPENCODE_VERSION:-v1.2.27}"
DOWNLOAD_SOURCE="${DOWNLOAD_SOURCE:-true}"

mkdir -p "${DIST_DIR}" "${SRC_DIR}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[opencode-bootstrap] missing command: $1" >&2
    exit 1
  fi
}

download() {
  local url="$1"
  local output="$2"
  echo "[opencode-bootstrap] downloading $(basename "${output}")"
  curl -fL "${url}" -o "${output}"
}

require_command curl

download "https://opencode.ai/install" "${SCRIPT_DIR}/install.sh"
chmod +x "${SCRIPT_DIR}/install.sh"

download \
  "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
  "${DIST_DIR}/opencode-linux-x64.tar.gz"

download \
  "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64-baseline.tar.gz" \
  "${DIST_DIR}/opencode-linux-x64-baseline.tar.gz"

if [ "${DOWNLOAD_SOURCE}" = "true" ]; then
  download \
    "https://github.com/anomalyco/opencode/archive/refs/tags/${OPENCODE_VERSION}.tar.gz" \
    "${SRC_DIR}/opencode-src-${OPENCODE_VERSION}.tar.gz"
fi

chmod +x "${SCRIPT_DIR}/install-in-container.sh"

echo "[opencode-bootstrap] completed"
echo "[opencode-bootstrap] version: ${OPENCODE_VERSION}"
echo "[opencode-bootstrap] next step:"
echo "  1. put this Java project into the container"
echo "  2. in container run: bash tools/opencode/install-in-container.sh"
