#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PROJECT_DIR="$(cd "${BASE_DIR}/../.." && pwd)"
DEFAULT_SERVER_PROJECT_DIR="/shared_data/app_data/www/default.qunar.com/webapps/ROOT"
PROJECT_DIR="${OPENCODE_PROJECT_DIR:-${SCRIPT_PROJECT_DIR}}"
DIST_DIR="${BASE_DIR}/dist"
SOURCE_SKILLS_DIR="${BASE_DIR}/skills"
SOURCE_AGENTS_DIR="${BASE_DIR}/agents"
TMP_DIR="${TMPDIR:-/tmp}/opencode-install-$$"
GLOBAL_CONFIG_DIR="${HOME}/.config/opencode"
GLOBAL_CONFIG_FILE="${GLOBAL_CONFIG_DIR}/opencode.json"
PROJECT_CONFIG_FILE=""
PROJECT_OPENCODE_DIR=""
PROJECT_SKILLS_DIR=""
PROJECT_AGENTS_DIR=""
PROJECT_RUNTIME_DIR=""
INSTALL_DIR=""
OPENCODE_BIN=""
ENV_FILE=""
ENV_SOURCE_LINE=""
PATH_LINE=""
LOG_FILE=""
PID_FILE=""
HOST_TAG="$(hostname 2>/dev/null || echo unknown-host)"
SELECTED_PACKAGE=""

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

finalize_exit_code() {
  local code=$?

  rm -rf "${TMP_DIR}" 2>/dev/null || true
  trap - EXIT

  if [ "${code}" -eq 0 ]; then
    exit 1
  fi

  exit 0
}

refresh_project_paths() {
  PROJECT_CONFIG_FILE="${PROJECT_DIR}/opencode.json"
  PROJECT_OPENCODE_DIR="${PROJECT_DIR}/.opencode"
  PROJECT_SKILLS_DIR="${PROJECT_OPENCODE_DIR}/skills"
  PROJECT_AGENTS_DIR="${PROJECT_OPENCODE_DIR}/agents"
  PROJECT_RUNTIME_DIR="${PROJECT_DIR}/.opencode-runtime"
  INSTALL_DIR="${PROJECT_RUNTIME_DIR}/bin"
  OPENCODE_BIN="${INSTALL_DIR}/opencode"
  ENV_FILE="${PROJECT_RUNTIME_DIR}/env.sh"
  ENV_SOURCE_LINE="[ -f \"${ENV_FILE}\" ] && . \"${ENV_FILE}\""
  PATH_LINE="export PATH=\"${INSTALL_DIR}:\$PATH\""
  LOG_FILE="${PROJECT_RUNTIME_DIR}/opencode-${HOST_TAG}.log"
  PID_FILE="${PROJECT_RUNTIME_DIR}/opencode-${HOST_TAG}.pid"
}

resolve_project_dir() {
  if [ "${PROJECT_DIR}" = "${SCRIPT_PROJECT_DIR}" ] && [ -d "${DEFAULT_SERVER_PROJECT_DIR}" ]; then
    PROJECT_DIR="${DEFAULT_SERVER_PROJECT_DIR}"
  fi

  refresh_project_paths
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

resolve_musl_fallback_package() {
  local primary_package="$1"

  case "${primary_package}" in
    opencode-linux-x64.tar.gz)
      echo "opencode-linux-x64-musl.tar.gz"
      ;;
    opencode-linux-x64-baseline.tar.gz)
      echo "opencode-linux-x64-baseline-musl.tar.gz"
      ;;
    opencode-linux-arm64.tar.gz)
      echo "opencode-linux-arm64-musl.tar.gz"
      ;;
    *)
      echo ""
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

  mkdir -p "$(dirname "${ENV_FILE}")"

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

log_execution_user() {
  echo "[opencode-init] execution user: $(id -un 2>/dev/null || whoami 2>/dev/null || echo unknown)"
  echo "[opencode-init] execution uid: $(id -u 2>/dev/null || echo unknown)"
  echo "[opencode-init] execution gid: $(id -g 2>/dev/null || echo unknown)"
  echo "[opencode-init] execution home: ${HOME}"
  echo "[opencode-init] execution pwd: $(pwd)"
  echo "[opencode-init] execution shell: ${SHELL:-unknown}"
  echo "[opencode-init] execution hostname: ${HOST_TAG}"
}

sync_project_skills() {
  mkdir -p "${PROJECT_OPENCODE_DIR}" "${PROJECT_SKILLS_DIR}"

  if [ ! -d "${SOURCE_SKILLS_DIR}" ]; then
    echo "[opencode-init] skills source directory not found: ${SOURCE_SKILLS_DIR}" >&2
    return 1
  fi

  cp -R "${SOURCE_SKILLS_DIR}/." "${PROJECT_SKILLS_DIR}/"
  echo "[opencode-init] project skills synced: ${PROJECT_SKILLS_DIR}"
  return 0
}

sync_project_agents() {
  mkdir -p "${PROJECT_OPENCODE_DIR}" "${PROJECT_AGENTS_DIR}"

  if [ ! -d "${SOURCE_AGENTS_DIR}" ]; then
    echo "[opencode-init] agents source directory not found: ${SOURCE_AGENTS_DIR}" >&2
    return 1
  fi

  cp -R "${SOURCE_AGENTS_DIR}/." "${PROJECT_AGENTS_DIR}/"
  echo "[opencode-init] project agents synced: ${PROJECT_AGENTS_DIR}"
  return 0
}

install_binary() {
  local package_name="$1"
  local extract_dir="${TMP_DIR}/extract"

  if [ ! -f "${DIST_DIR}/${package_name}" ]; then
    echo "[opencode-init] package not found: ${DIST_DIR}/${package_name}" >&2
    return 1
  fi

  rm -rf "${extract_dir}"
  mkdir -p "${INSTALL_DIR}" "${extract_dir}"
  tar -xzf "${DIST_DIR}/${package_name}" -C "${extract_dir}"

  if [ ! -f "${extract_dir}/opencode" ]; then
    echo "[opencode-init] extracted binary not found in package: ${package_name}" >&2
    return 1
  fi

  cp "${extract_dir}/opencode" "${OPENCODE_BIN}"
  chmod 755 "${OPENCODE_BIN}"
  SELECTED_PACKAGE="${package_name}"
  echo "[opencode-init] binary installed: ${OPENCODE_BIN}"
  echo "[opencode-init] selected package: ${SELECTED_PACKAGE}"
  return 0
}

check_opencode_binary() {
  local version_output
  local fallback_package=""

  if version_output="$("${OPENCODE_BIN}" --version 2>&1)"; then
    echo "[opencode-init] version: ${version_output}"
    return 0
  fi

  echo "${version_output}" >&2

  fallback_package="$(resolve_musl_fallback_package "${SELECTED_PACKAGE}")"
  if printf '%s' "${version_output}" | grep -q "GLIBC_" && [ -n "${fallback_package}" ] && [ -f "${DIST_DIR}/${fallback_package}" ]; then
    echo "[opencode-init] detected glibc compatibility issue, retrying with musl package: ${fallback_package}"

    if ! install_binary "${fallback_package}"; then
      return 1
    fi

    if version_output="$("${OPENCODE_BIN}" --version 2>&1)"; then
      echo "[opencode-init] version: ${version_output}"
      return 0
    fi

    echo "${version_output}" >&2
  fi

  echo "[opencode-init] opencode binary validation failed: ${OPENCODE_BIN}" >&2
  return 1
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
    export PATH="${INSTALL_DIR}:${PATH}"
    export OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD}"
    nohup "${OPENCODE_BIN}" serve --hostname "${OPENCODE_SERVER_HOSTNAME}" --port "${OPENCODE_SERVER_PORT}" > "${LOG_FILE}" 2>&1 &
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
require_command cp

refresh_project_paths
resolve_project_dir

PACKAGE="$(resolve_package)"

mkdir -p "${TMP_DIR}" "${INSTALL_DIR}" "${PROJECT_RUNTIME_DIR}"
trap finalize_exit_code EXIT

if ! install_binary "${PACKAGE}"; then
  exit 1
fi
write_env_file
append_path_if_missing "${HOME}/.bashrc"
append_path_if_missing "${HOME}/.bash_profile"
append_path_if_missing "${HOME}/.profile"

. "${ENV_FILE}"
CONFIG_FILE="$(resolve_config_file)"
write_opencode_config "${CONFIG_FILE}"
if ! sync_project_skills; then
  exit 1
fi
if ! sync_project_agents; then
  exit 1
fi

echo "[opencode-init] install success"
log_execution_user
echo "[opencode-init] runtime dir: ${PROJECT_RUNTIME_DIR}"
echo "[opencode-init] model: ${OPENCODE_MODEL}"
echo "[opencode-init] config scope: ${OPENCODE_CONFIG_SCOPE}"
echo "[opencode-init] project dir: ${PROJECT_DIR}"
show_auth_hint_if_needed
if ! check_opencode_binary; then
  exit 1
fi
if ! start_opencode_server; then
  exit 1
fi

exit 0
