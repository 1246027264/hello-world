#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${BASE_DIR}/dist"
INSTALL_DIR="${HOME}/.opencode/bin"
TMP_DIR="${TMPDIR:-/tmp}/opencode-install-$$"
PATH_LINE='export PATH="$HOME/.opencode/bin:$PATH"'

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[opencode-init] missing command: $1" >&2
    exit 1
  fi
}

append_path_if_missing() {
  local file="$1"

  if [ -f "${file}" ]; then
    if ! grep -Fq "${PATH_LINE}" "${file}" >/dev/null 2>&1; then
      printf '\n# opencode\n%s\n' "${PATH_LINE}" >> "${file}"
    fi
  else
    printf '# opencode\n%s\n' "${PATH_LINE}" > "${file}"
  fi
}

resolve_package() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    x86_64)
      if grep -qwi "avx2" /proc/cpuinfo; then
        echo "opencode-linux-x64.tar.gz"
      else
        echo "opencode-linux-x64-baseline.tar.gz"
      fi
      ;;
    aarch64|arm64)
      echo "opencode-linux-arm64.tar.gz"
      ;;
    *)
      echo "[opencode-init] unsupported arch: ${arch}" >&2
      exit 1
      ;;
  esac
}

require_command bash
require_command tar
require_command grep

if [ ! -x "${BASE_DIR}/install.sh" ]; then
  echo "[opencode-init] install.sh not found or not executable: ${BASE_DIR}/install.sh" >&2
  exit 1
fi

PACKAGE="$(resolve_package)"

if [ ! -f "${DIST_DIR}/${PACKAGE}" ]; then
  echo "[opencode-init] package not found: ${DIST_DIR}/${PACKAGE}" >&2
  exit 1
fi

mkdir -p "${TMP_DIR}" "${INSTALL_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

tar -xzf "${DIST_DIR}/${PACKAGE}" -C "${TMP_DIR}"

if [ ! -f "${TMP_DIR}/opencode" ]; then
  echo "[opencode-init] extracted binary not found: ${TMP_DIR}/opencode" >&2
  exit 1
fi

chmod +x "${TMP_DIR}/opencode"
bash "${BASE_DIR}/install.sh" --binary "${TMP_DIR}/opencode" --no-modify-path

append_path_if_missing "${HOME}/.bashrc"
append_path_if_missing "${HOME}/.bash_profile"
append_path_if_missing "${HOME}/.profile"

export PATH="${INSTALL_DIR}:${PATH}"

echo "[opencode-init] install success"
echo "[opencode-init] version: $(opencode --version)"
echo "[opencode-init] if current shell does not pick PATH automatically, run:"
echo "  export PATH=\"\$HOME/.opencode/bin:\$PATH\""
