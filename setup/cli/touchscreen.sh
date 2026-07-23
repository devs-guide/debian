#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/touchscreen.sh
## Minimal Debian touchscreen setup runner.
## Local usage:
##   ./setup/cli/touchscreen.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen.sh | bash

set -euo pipefail

log() { printf '[setup.cli.touchscreen] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.touchscreen][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.touchscreen}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "cli/touchscreen.yml"
)
TOUCHSCREEN_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
TOUCHSCREEN_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${TOUCHSCREEN_PLAYBOOK_REL}"
TOUCHSCREEN_EXTRA_VARS_PATH="${TMP_DIR}/touchscreen.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_TOUCHSCREEN_MODE:-apply}}"
TOUCHSCREEN_ENABLE="${DEBIAN_TOUCHSCREEN_ENABLE:-}"
TOUCHSCREEN_USER="${DEBIAN_TOUCHSCREEN_USER:-app}"
TOUCHSCREEN_MATCH="${DEBIAN_TOUCHSCREEN_MATCH:-eGalax|D-WAV|Titan6001|TouchController|Touchscreen}"
TOUCHSCREEN_PRIMARY_ID="${DEBIAN_TOUCHSCREEN_PRIMARY_ID:-}"
TOUCHSCREEN_DISABLE_IDS="${DEBIAN_TOUCHSCREEN_DISABLE_IDS:-}"
TOUCHSCREEN_OUTPUT="${DEBIAN_TOUCHSCREEN_OUTPUT:-}"
TOUCHSCREEN_MATRIX="${DEBIAN_TOUCHSCREEN_MATRIX:-identity}"
TOUCHSCREEN_CUSTOM_MATRIX="${DEBIAN_TOUCHSCREEN_CUSTOM_MATRIX:-1 0 0 0 1 0 0 0 1}"
TOUCHSCREEN_CONFIG_FILE="${DEBIAN_TOUCHSCREEN_CONFIG_FILE:-/etc/default/debian-touchscreen}"
TOUCHSCREEN_APPLY_SCRIPT_PATH="${DEBIAN_TOUCHSCREEN_APPLY_SCRIPT_PATH:-/usr/local/bin/debian-touchscreen-apply}"
TOUCHSCREEN_LIST_SCRIPT_PATH="${DEBIAN_TOUCHSCREEN_LIST_SCRIPT_PATH:-/usr/local/bin/debian-touchscreen-list}"
TOUCHSCREEN_XSESSION_HOOK_DIR="${DEBIAN_TOUCHSCREEN_XSESSION_HOOK_DIR:-/home/${TOUCHSCREEN_USER}/.config/debian/xsession.d}"
TOUCHSCREEN_HOOK_NAME="${DEBIAN_TOUCHSCREEN_HOOK_NAME:-20-touchscreen.sh}"
TOUCHSCREEN_RUNTIME_FACTS_PATH="${DEBIAN_TOUCHSCREEN_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/touchscreen.yml}"
TOUCHSCREEN_INSTALL_PACKAGES="${DEBIAN_TOUCHSCREEN_INSTALL_PACKAGES:-1}"
TOUCHSCREEN_PACKAGES="${DEBIAN_TOUCHSCREEN_PACKAGES:-xinput xinput-calibrator xserver-xorg-input-evdev}"
TOUCHSCREEN_INSTALL_EVTEST="${DEBIAN_TOUCHSCREEN_INSTALL_EVTEST:-0}"
TOUCHSCREEN_ENABLE_SET=0
REFRESH="${REFRESH:-0}"

declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

if [[ -n "${DEBIAN_TOUCHSCREEN_ENABLE+x}" ]]; then
  TOUCHSCREEN_ENABLE_SET=1
fi

reset.feature.tmp.cache() {
  case "${REFRESH,,}" in
    1|true|yes|y|on)
      log "REFRESH=1; clearing feature tmp cache under ${TMP_DIR}"
      rm -rf "${TMP_DIR}"
      ;;
  esac
}

source.release.common() {
  local script_dir=""

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -r "${script_dir}/${LOCAL_COMMON_HELPER}" ]]; then
    # shellcheck source=setup/release.common.sh
    source "${script_dir}/${LOCAL_COMMON_HELPER}"
    return
  fi

  mkdir -p "${TMP_DIR}"
  log "Fetching shared helper: ${COMMON_HELPER_URL}"
  if ! wget -qO "${COMMON_HELPER_PATH}" "${COMMON_HELPER_URL}"; then
    log.error "Failed to fetch shared helper: ${COMMON_HELPER_URL}"
    exit 1
  fi
  # shellcheck source=/tmp/ansible/debian/cli.touchscreen/release.common.sh
  source "${COMMON_HELPER_PATH}"
}

is.true() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

yaml.quote() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

bool.yaml() {
  if is.true "${1:-false}"; then
    printf 'true'
  else
    printf 'false'
  fi
}

yaml.string.list() {
  local raw="${1:-}"
  local item=""
  local -a values=()
  local first=1

  read -r -a values <<< "${raw}"
  if (( ${#values[@]} == 0 )); then
    printf '[]'
    return 0
  fi

  printf '['
  for item in "${values[@]}"; do
    if (( first )); then
      first=0
    else
      printf ', '
    fi
    printf '%s' "$(yaml.quote "${item}")"
  done
  printf ']'
}

require.valid.mode() {
  case "${FEATURE_MODE}" in
    preflight|apply|disable) ;;
    *)
      log.error "Unsupported mode: ${FEATURE_MODE}"
      log.error "Use one of: preflight, apply, disable"
      exit 1
      ;;
  esac
}

require.debian.host() {
  if [[ ! -f /etc/debian_version ]]; then
    log.error "This feature runner expects a Debian host."
    exit 1
  fi
}

collect.sudo.env.args() {
  local -n _out="$1"

  _out=(
    "DEBIAN_TOUCHSCREEN_ENABLE=${TOUCHSCREEN_ENABLE}"
    "DEBIAN_TOUCHSCREEN_MODE=${FEATURE_MODE}"
    "DEBIAN_TOUCHSCREEN_USER=${TOUCHSCREEN_USER}"
    "DEBIAN_TOUCHSCREEN_MATCH=${TOUCHSCREEN_MATCH}"
    "DEBIAN_TOUCHSCREEN_PRIMARY_ID=${TOUCHSCREEN_PRIMARY_ID}"
    "DEBIAN_TOUCHSCREEN_DISABLE_IDS=${TOUCHSCREEN_DISABLE_IDS}"
    "DEBIAN_TOUCHSCREEN_OUTPUT=${TOUCHSCREEN_OUTPUT}"
    "DEBIAN_TOUCHSCREEN_MATRIX=${TOUCHSCREEN_MATRIX}"
    "DEBIAN_TOUCHSCREEN_CUSTOM_MATRIX=${TOUCHSCREEN_CUSTOM_MATRIX}"
    "DEBIAN_TOUCHSCREEN_CONFIG_FILE=${TOUCHSCREEN_CONFIG_FILE}"
    "DEBIAN_TOUCHSCREEN_APPLY_SCRIPT_PATH=${TOUCHSCREEN_APPLY_SCRIPT_PATH}"
    "DEBIAN_TOUCHSCREEN_LIST_SCRIPT_PATH=${TOUCHSCREEN_LIST_SCRIPT_PATH}"
    "DEBIAN_TOUCHSCREEN_XSESSION_HOOK_DIR=${TOUCHSCREEN_XSESSION_HOOK_DIR}"
    "DEBIAN_TOUCHSCREEN_HOOK_NAME=${TOUCHSCREEN_HOOK_NAME}"
    "DEBIAN_TOUCHSCREEN_RUNTIME_FACTS_PATH=${TOUCHSCREEN_RUNTIME_FACTS_PATH}"
    "DEBIAN_TOUCHSCREEN_INSTALL_PACKAGES=${TOUCHSCREEN_INSTALL_PACKAGES}"
    "DEBIAN_TOUCHSCREEN_PACKAGES=${TOUCHSCREEN_PACKAGES}"
    "DEBIAN_TOUCHSCREEN_INSTALL_EVTEST=${TOUCHSCREEN_INSTALL_EVTEST}"
    "DEBIAN_TOUCHSCREEN_SUDO_REEXEC=1"
  )
}

current.script.path() {
  local source_path="${BASH_SOURCE[0]:-}"

  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*)
      return 1
      ;;
  esac

  if [[ -r "${source_path}" ]]; then
    readlink -f "${source_path}" 2>/dev/null || printf '%s\n' "${source_path}"
    return 0
  fi

  return 1
}

ensure.root.or.sudo.reexec() {
  local script_path=""
  local -a sudo_env

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${DEBIAN_TOUCHSCREEN_SUDO_REEXEC:-0}" = "1" ]]; then
    log.error "sudo re-entry was requested but the script is still not running as root."
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    log.error "This setup requires root privileges. Install sudo or run as root."
    exit 1
  fi

  log "Root privileges required; requesting sudo..."
  if ! sudo -v; then
    log.error "sudo authentication failed or was cancelled."
    exit 1
  fi

  collect.sudo.env.args sudo_env
  if script_path="$(current.script.path)"; then
    exec sudo -E env "${sudo_env[@]}" bash "${script_path}" "$@"
  fi

  if command -v wget >/dev/null 2>&1; then
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${PAGES_BASE_URL}/setup/cli/touchscreen.sh" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because wget is unavailable."
  exit 1
}

resolve.defaults() {
  if [[ "${TOUCHSCREEN_ENABLE_SET}" -eq 0 ]]; then
    case "${FEATURE_MODE}" in
      disable) TOUCHSCREEN_ENABLE=0 ;;
      *) TOUCHSCREEN_ENABLE=1 ;;
    esac
  fi
}

use.local.feature.files() {
  local script_dir repo_root file

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"

  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ ! -r "${repo_root}/ansible/group_vars/${file}" ]]; then
      return 1
    fi
  done

  if [[ -r "${repo_root}/ansible/${TOUCHSCREEN_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    TOUCHSCREEN_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${TOUCHSCREEN_PLAYBOOK_REL}"
    reset.feature.extra.vars.args
    log "Using local feature files from ${repo_root}"
    return 0
  fi

  return 1
}

fetch.feature.file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "${dest}")"
  log "Fetching feature file: ${url}"
  if ! wget -qO "${dest}" "${url}"; then
    log.error "Failed to fetch feature file: ${url}"
    exit 1
  fi
  if [[ ! -s "${dest}" ]]; then
    log.error "Feature file is empty: ${url}"
    exit 1
  fi
}

reset.feature.extra.vars.args() {
  FEATURE_GROUP_VARS_ARGS=()
  local file=""

  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ -f "${PLAYBOOK_GROUP_VARS_DIR}/${file}" ]]; then
      FEATURE_GROUP_VARS_ARGS+=( -e "@${PLAYBOOK_GROUP_VARS_DIR}/${file}" )
    fi
  done
}

prepare.feature.files() {
  if use.local.feature.files; then
    return
  fi

  mkdir -p "${PLAYBOOK_GROUP_VARS_DIR}"
  for file in "${GROUP_VARS_FILES[@]}"; do
    fetch.feature.file "${PAGES_BASE_URL}/ansible/group_vars/${file}" "${PLAYBOOK_GROUP_VARS_DIR}/${file}"
  done

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${TOUCHSCREEN_PLAYBOOK_REL}" "${TOUCHSCREEN_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.touchscreen.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${TOUCHSCREEN_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
touchscreen_enable: $(bool.yaml "${TOUCHSCREEN_ENABLE}")
touchscreen_mode: $(yaml.quote "${FEATURE_MODE}")
touchscreen_user: $(yaml.quote "${TOUCHSCREEN_USER}")
touchscreen_match: $(yaml.quote "${TOUCHSCREEN_MATCH}")
touchscreen_primary_id: $(yaml.quote "${TOUCHSCREEN_PRIMARY_ID}")
touchscreen_disable_ids: $(yaml.quote "${TOUCHSCREEN_DISABLE_IDS}")
touchscreen_output: $(yaml.quote "${TOUCHSCREEN_OUTPUT}")
touchscreen_matrix: $(yaml.quote "${TOUCHSCREEN_MATRIX}")
touchscreen_custom_matrix: $(yaml.quote "${TOUCHSCREEN_CUSTOM_MATRIX}")
touchscreen_config_file: $(yaml.quote "${TOUCHSCREEN_CONFIG_FILE}")
touchscreen_apply_script_path: $(yaml.quote "${TOUCHSCREEN_APPLY_SCRIPT_PATH}")
touchscreen_list_script_path: $(yaml.quote "${TOUCHSCREEN_LIST_SCRIPT_PATH}")
touchscreen_xsession_hook_dir: $(yaml.quote "${TOUCHSCREEN_XSESSION_HOOK_DIR}")
touchscreen_hook_script: $(yaml.quote "${TOUCHSCREEN_HOOK_NAME}")
touchscreen_runtime_facts_path: $(yaml.quote "${TOUCHSCREEN_RUNTIME_FACTS_PATH}")
touchscreen_install_packages: $(bool.yaml "${TOUCHSCREEN_INSTALL_PACKAGES}")
touchscreen_packages: $(yaml.string.list "${TOUCHSCREEN_PACKAGES}")
touchscreen_install_evtest: $(bool.yaml "${TOUCHSCREEN_INSTALL_EVTEST}")
EOF_VARS
  log "Prepared touchscreen extra-vars: ${TOUCHSCREEN_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Mode: ${FEATURE_MODE}"
  log "Touchscreen enabled: ${TOUCHSCREEN_ENABLE}"
  log "User: ${TOUCHSCREEN_USER}"
  log "Match: ${TOUCHSCREEN_MATCH}"
  log "Install packages: ${TOUCHSCREEN_INSTALL_PACKAGES}"
  log "Packages: ${TOUCHSCREEN_PACKAGES}"
  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/touchscreen.sh | bash"
}

run.touchscreen.feature() {
  write.touchscreen.extra.vars.file
  log "Running Debian touchscreen feature..."
  run.feature.playbook "${TOUCHSCREEN_PLAYBOOK_PATH}" -e "@${TOUCHSCREEN_EXTRA_VARS_PATH}"
}

main() {
  reset.feature.tmp.cache
  source.release.common
  ensure.root.or.sudo.reexec "$@"
  require.root
  require.apt
  require.debian.host
  require.valid.mode
  resolve.defaults
  ensure.local.ansible

  run.preflight
  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    return 0
  fi

  prepare.feature.files
  run.touchscreen.feature
}

main "$@"
