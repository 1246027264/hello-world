#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
SRC_DIR="${SCRIPT_DIR}/src"

OPENCODE_VERSION="${OPENCODE_VERSION:-v1.2.27}"
DOWNLOAD_SOURCE="${DOWNLOAD_SOURCE:-true}"
DOWNLOAD_REGION="${DOWNLOAD_REGION:-cn}"
INSTALL_SCRIPT_URL="${INSTALL_SCRIPT_URL:-}"
GITHUB_PROXY_PREFIX="${GITHUB_PROXY_PREFIX:-}"

mkdir -p "${DIST_DIR}" "${SRC_DIR}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[opencode-bootstrap] missing command: $1" >&2
    exit 1
  fi
}

download() {
  local output="$1"
  shift
  local tmp_file="${output}.tmp"
  local url

  rm -f "${tmp_file}"

  for url in "$@"; do
    if [ -z "${url}" ]; then
      continue
    fi

    echo "[opencode-bootstrap] downloading $(basename "${output}")"
    echo "[opencode-bootstrap] trying: ${url}"

    if curl -fL --retry 2 --connect-timeout 15 "${url}" -o "${tmp_file}"; then
      mv "${tmp_file}" "${output}"
      return 0
    fi

    rm -f "${tmp_file}"
  done

  echo "[opencode-bootstrap] failed to download $(basename "${output}")" >&2
  exit 1
}

github_candidates() {
  local path="$1"

  if [ -n "${GITHUB_PROXY_PREFIX}" ]; then
    printf '%s\n' "${GITHUB_PROXY_PREFIX}https://github.com/${path}"
  fi

  if [ "${DOWNLOAD_REGION}" = "cn" ]; then
    printf '%s\n' \
      "https://mirror.ghproxy.com/https://github.com/${path}" \
      "https://gh-proxy.com/https://github.com/${path}" \
      "https://kkgithub.com/${path}"
  fi

  printf '%s\n' "https://github.com/${path}"
}

install_script_candidates() {
  if [ -n "${INSTALL_SCRIPT_URL}" ]; then
    printf '%s\n' "${INSTALL_SCRIPT_URL}"
    return
  fi

  if [ "${DOWNLOAD_REGION}" = "cn" ]; then
    printf '%s\n' \
      "https://opencode.ai/install" \
      "https://cdn.jsdelivr.net/gh/anomalyco/opencode@dev/install" \
      "https://raw.githubusercontent.com/anomalyco/opencode/dev/install"
    return
  fi

  printf '%s\n' "https://opencode.ai/install"
}

require_command curl

download "${SCRIPT_DIR}/install.sh" $(install_script_candidates)
chmod +x "${SCRIPT_DIR}/install.sh"

download "${DIST_DIR}/opencode-linux-x64.tar.gz" \
  $(github_candidates "anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64.tar.gz")

download "${DIST_DIR}/opencode-linux-x64-baseline.tar.gz" \
  $(github_candidates "anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64-baseline.tar.gz")

download "${DIST_DIR}/opencode-linux-x64-musl.tar.gz" \
  $(github_candidates "anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64-musl.tar.gz")

download "${DIST_DIR}/opencode-linux-x64-baseline-musl.tar.gz" \
  $(github_candidates "anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64-baseline-musl.tar.gz")

if [ "${DOWNLOAD_SOURCE}" = "true" ]; then
  download "${SRC_DIR}/opencode-src-${OPENCODE_VERSION}.tar.gz" \
    $(github_candidates "anomalyco/opencode/archive/refs/tags/${OPENCODE_VERSION}.tar.gz")
fi

chmod +x "${SCRIPT_DIR}/install-in-container.sh"

echo "[opencode-bootstrap] completed"
echo "[opencode-bootstrap] version: ${OPENCODE_VERSION}"
echo "[opencode-bootstrap] region preset: ${DOWNLOAD_REGION}"
echo "[opencode-bootstrap] next step:"
echo "  1. put this Java project into the container"
echo "  2. in container run: ANTHROPIC_API_KEY=your_key OPENCODE_MODEL=anthropic/claude-sonnet-4-5 bash tools/opencode/install-in-container.sh"
