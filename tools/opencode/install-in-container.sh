#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${BASE_DIR}/../.." && pwd)"
DIST_DIR="${BASE_DIR}/dist"
INSTALL_DIR="${HOME}/.opencode/bin"
TMP_DIR="${TMPDIR:-/tmp}/opencode-install-$$"
CONFIG_DIR="${HOME}/.config/opencode"
ENV_FILE="${CONFIG_DIR}/env.sh"
GLOBAL_CONFIG_FILE="${CONFIG_DIR}/opencode.json"
PROJECT_CONFIG_FILE="${PROJECT_DIR}/opencode.json"
ENV_SOURCE_LINE='[ -f "$HOME/.config/opencode/env.sh" ] && . "$HOME/.config/opencode/env.sh"'
PATH_LINE='export PATH="$HOME/.opencode/bin:$PATH"'

OPENCODE_MODEL="deepseek/deepseek-chat"
OPENCODE_CONFIG_SCOPE="${OPENCODE_CONFIG_SCOPE:-project}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com/v1}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-sk-1c14ed4470fe42aa84684b58cdd7a7e6}"
FORCE_WRITE_OPENCODE_CONFIG="${FORCE_WRITE_OPENCODE_CONFIG:-false}"
START_OPENCODE_AFTER_INSTALL="${START_OPENCODE_AFTER_INSTALL:-true}"
RESTART_LOGIN_SHELL_AFTER_INSTALL="${RESTART_LOGIN_SHELL_AFTER_INSTALL:-false}"
PERSISTED_ENV_VARS="${PERSISTED_ENV_VARS:-DEEPSEEK_API_KEY DEEPSEEK_BASE_URL}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[opencode-init] missing command: $1" >&2
    exit 1
  fi
}

append_path_if_missing() {
  local file="$1"

  mkdir -p "$(dirname "${file}")"

  if [ -f "${file}" ]; then
    if ! grep -Fq "${ENV_SOURCE_LINE}" "${file}" >/dev/null 2>&1; then
      printf '\n# opencode\n%s\n' "${ENV_SOURCE_LINE}" >> "${file}"
    fi
  else
    printf '# opencode\n%s\n' "${ENV_SOURCE_LINE}" > "${file}"
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

resolve_config_file() {
  case "${OPENCODE_CONFIG_SCOPE}" in
    project)
      echo "${PROJECT_CONFIG_FILE}"
      ;;
    global)
      echo "${GLOBAL_CONFIG_FILE}"
      ;;
    *)
      echo "[opencode-init] unsupported OPENCODE_CONFIG_SCOPE: ${OPENCODE_CONFIG_SCOPE}" >&2
      exit 1
      ;;
  esac
}

backup_if_exists() {
  local file="$1"
  local backup_file

  if [ -f "${file}" ]; then
    backup_file="${file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${file}" "${backup_file}"
    echo "[opencode-init] backup created: ${backup_file}"
  fi
}

write_env_file() {
  local var_name
  local value
  local escaped_value

  mkdir -p "${CONFIG_DIR}"

  {
    echo "#!/usr/bin/env bash"
    echo "# managed by tools/opencode/install-in-container.sh"
    echo "${PATH_LINE}"

    for var_name in ${PERSISTED_ENV_VARS}; do
      value="${!var_name:-}"
      if [ -n "${value}" ]; then
        escaped_value=$(printf '%q' "${value}")
        printf 'export %s=%s\n' "${var_name}" "${escaped_value}"
      fi
    done
  } > "${ENV_FILE}"

  chmod 600 "${ENV_FILE}"
}

write_opencode_config() {
  local config_file="$1"
  mkdir -p "$(dirname "${config_file}")"

  if [ -f "${config_file}" ] && [ "${FORCE_WRITE_OPENCODE_CONFIG}" != "true" ]; then
    echo "[opencode-init] config exists, skip writing: ${config_file}"
    echo "[opencode-init] set FORCE_WRITE_OPENCODE_CONFIG=true to overwrite it"
    return 0
  fi

  backup_if_exists "${config_file}"

  {
    echo "{"
    echo "  \"\$schema\": \"https://opencode.ai/config.json\","
    echo "  \"model\": \"${OPENCODE_MODEL}\","
    echo "  \"provider\": {"
    echo "    \"deepseek\": {"
    echo "      \"api\": \"openai-completions\","
    echo "      \"options\": {"
    echo "        \"baseURL\": \"${DEEPSEEK_BASE_URL}\","
    echo "        \"apiKey\": \"${DEEPSEEK_API_KEY}\""
    echo "      }"
    echo "    }"
    echo "  },"
    echo "  \"permission\": {"
    echo "    \"skill\": {"
    echo "      \"*\": \"allow\""
    echo "    }"
    echo "  }"
    echo "}"
  } > "${config_file}"

  echo "[opencode-init] config written: ${config_file}"
}

show_auth_hint_if_needed() {
  local var_name

  for var_name in ${PERSISTED_ENV_VARS}; do
    if [ -n "${!var_name:-}" ]; then
      return 0
    fi
  done

  echo "[opencode-init] no provider credential detected in current shell"
  echo "[opencode-init] DEEPSEEK_API_KEY is not set in current shell"
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

write_env_file
append_path_if_missing "${HOME}/.bashrc"
append_path_if_missing "${HOME}/.bash_profile"
append_path_if_missing "${HOME}/.profile"

. "${ENV_FILE}"
CONFIG_FILE="$(resolve_config_file)"
write_opencode_config "${CONFIG_FILE}"

echo "[opencode-init] install success"
echo "[opencode-init] version: $(opencode --version)"
echo "[opencode-init] model: ${OPENCODE_MODEL}"
echo "[opencode-init] config scope: ${OPENCODE_CONFIG_SCOPE}"
show_auth_hint_if_needed

if [ "${START_OPENCODE_AFTER_INSTALL}" = "true" ]; then
  echo "[opencode-init] starting opencode"
  exec opencode
fi

if [ "${RESTART_LOGIN_SHELL_AFTER_INSTALL}" = "true" ] && [ -t 0 ] && [ -t 1 ]; then
  echo "[opencode-init] restarting login shell"
  exec "${SHELL:-/bin/bash}" -il
fi

echo "[opencode-init] next command:"
echo "  . \"${ENV_FILE}\" && opencode"
