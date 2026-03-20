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
LOG_FILE="${PROJECT_DIR}/opencode.log"
PID_FILE="${PROJECT_DIR}/opencode.pid"

OPENCODE_MODEL="deepseek/deepseek-chat"
OPENCODE_CONFIG_SCOPE="${OPENCODE_CONFIG_SCOPE:-project}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com/v1}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-sk-1c14ed4470fe42aa84684b58cdd7a7e6}"
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-your-password}"
OPENCODE_SERVER_HOSTNAME="${OPENCODE_SERVER_HOSTNAME:-0.0.0.0}"
OPENCODE_SERVER_PORT="${OPENCODE_SERVER_PORT:-4096}"
FORCE_WRITE_OPENCODE_CONFIG="${FORCE_WRITE_OPENCODE_CONFIG:-false}"
PERSISTED_ENV_VARS="${PERSISTED_ENV_VARS:-DEEPSEEK_API_KEY DEEPSEEK_BASE_URL OPENCODE_SERVER_PASSWORD}"

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

start_opencode_server() {
  local existing_pid=""
  local started_pid=""
  local wait_seconds=15
  local i

  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" >/dev/null 2>&1; then
    echo "[opencode-init] opencode server already running, pid: $(cat "${PID_FILE}")"
    echo "[opencode-init] log file: ${LOG_FILE}"
    return 0
  fi

  if command -v pgrep >/dev/null 2>&1; then
    existing_pid="$(pgrep -f "opencode serve --hostname ${OPENCODE_SERVER_HOSTNAME} --port ${OPENCODE_SERVER_PORT}" | head -n 1 || true)"
  fi

  if [ -n "${existing_pid}" ]; then
    echo "[opencode-init] opencode server already running, pid: ${existing_pid}"
    echo "[opencode-init] log file: ${LOG_FILE}"
    echo "${existing_pid}" > "${PID_FILE}"
    return 0
  fi

  (
    cd "${PROJECT_DIR}"
    export PATH="${HOME}/.opencode/bin:${PATH}"
    export OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD}"
    nohup opencode serve --hostname "${OPENCODE_SERVER_HOSTNAME}" --port "${OPENCODE_SERVER_PORT}" > "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"
  )

  if [ ! -f "${PID_FILE}" ]; then
    echo "[opencode-init] failed to capture opencode server pid" >&2
    return 1
  fi

  started_pid="$(cat "${PID_FILE}")"

  for i in $(seq 1 "${wait_seconds}"); do
    if ! kill -0 "${started_pid}" >/dev/null 2>&1; then
      break
    fi

    if command -v curl >/dev/null 2>&1; then
      if curl -s -u "opencode:${OPENCODE_SERVER_PASSWORD}" "http://127.0.0.1:${OPENCODE_SERVER_PORT}/global/health" >/dev/null 2>&1; then
        echo "[opencode-init] opencode server started"
        echo "[opencode-init] pid: ${started_pid}"
        echo "[opencode-init] password: ${OPENCODE_SERVER_PASSWORD}"
        echo "[opencode-init] url: http://127.0.0.1:${OPENCODE_SERVER_PORT}/doc"
        echo "[opencode-init] log file: ${LOG_FILE}"
        return 0
      fi
    else
      if [ "${i}" -ge 3 ]; then
        echo "[opencode-init] opencode server started"
        echo "[opencode-init] pid: ${started_pid}"
        echo "[opencode-init] password: ${OPENCODE_SERVER_PASSWORD}"
        echo "[opencode-init] url: http://127.0.0.1:${OPENCODE_SERVER_PORT}/doc"
        echo "[opencode-init] log file: ${LOG_FILE}"
        return 0
      fi
    fi

    sleep 1
  done

  if [ -f "${LOG_FILE}" ]; then
    echo "[opencode-init] last log lines:" >&2
    tail -n 50 "${LOG_FILE}" >&2 || true
  fi

  echo "[opencode-init] failed to start opencode server" >&2
  echo "[opencode-init] check log: ${LOG_FILE}" >&2
  return 1
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
if ! start_opencode_server; then
  exit 1
fi

exit 0
