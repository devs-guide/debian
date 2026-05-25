#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/openbox
## Minimal Debian Openbox setup runner.
## Local usage:
##   ./setup/cli/openbox.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox | bash

set -euo pipefail

log() { printf '[setup.cli.openbox] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.openbox][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.openbox}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "cli/openbox.yml"
)
OPENBOX_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
OPENBOX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${OPENBOX_PLAYBOOK_REL}"
OPENBOX_EXTRA_VARS_PATH="${TMP_DIR}/openbox.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_OPENBOX_MODE:-apply}}"
OPENBOX_ENABLE="${DEBIAN_OPENBOX_ENABLE:-}"
OPENBOX_USER="${DEBIAN_OPENBOX_USER:-app}"
OPENBOX_SESSION_COMMAND="${DEBIAN_OPENBOX_SESSION_COMMAND:-/usr/bin/openbox-session}"
OPENBOX_XINITRC_PATH="${DEBIAN_OPENBOX_XINITRC_PATH:-/home/${OPENBOX_USER}/.xinitrc}"
OPENBOX_XSESSION_HOOK_DIR="${DEBIAN_OPENBOX_XSESSION_HOOK_DIR:-/home/${OPENBOX_USER}/.config/debian/xsession.d}"
OPENBOX_MANAGE_XINITRC="${DEBIAN_OPENBOX_MANAGE_XINITRC:-1}"
OPENBOX_MANAGE_XSESSION_HOOK_DIR="${DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR:-1}"
OPENBOX_FULLSCREEN="${DEBIAN_OPENBOX_FULLSCREEN:-0}"
OPENBOX_FULLSCREEN_MATCH="${DEBIAN_OPENBOX_FULLSCREEN_MATCH:-xclock}"
OPENBOX_FULLSCREEN_RETRIES="${DEBIAN_OPENBOX_FULLSCREEN_RETRIES:-24}"
OPENBOX_FULLSCREEN_DELAY_MS="${DEBIAN_OPENBOX_FULLSCREEN_DELAY_MS:-250}"
OPENBOX_FULLSCREEN_HELPER="${DEBIAN_OPENBOX_FULLSCREEN_HELPER:-/usr/local/bin/debian-openbox-fullscreen}"
OPENBOX_RUNTIME_FACTS_PATH="${DEBIAN_OPENBOX_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/openbox.yml}"
OPENBOX_INSTALL_PACKAGES="${DEBIAN_OPENBOX_INSTALL_PACKAGES:-1}"
OPENBOX_PACKAGES="${DEBIAN_OPENBOX_PACKAGES:-openbox}"
OPENBOX_ENABLE_SET=0
REFRESH="${REFRESH:-0}"

declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

if [[ -n "${DEBIAN_OPENBOX_ENABLE+x}" ]]; then
  OPENBOX_ENABLE_SET=1
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
  # shellcheck source=/tmp/ansible/debian/cli.openbox/release.common.sh
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
    "DEBIAN_OPENBOX_ENABLE=${OPENBOX_ENABLE}"
    "DEBIAN_OPENBOX_MODE=${FEATURE_MODE}"
    "DEBIAN_OPENBOX_USER=${OPENBOX_USER}"
    "DEBIAN_OPENBOX_SESSION_COMMAND=${OPENBOX_SESSION_COMMAND}"
    "DEBIAN_OPENBOX_XINITRC_PATH=${OPENBOX_XINITRC_PATH}"
    "DEBIAN_OPENBOX_XSESSION_HOOK_DIR=${OPENBOX_XSESSION_HOOK_DIR}"
    "DEBIAN_OPENBOX_MANAGE_XINITRC=${OPENBOX_MANAGE_XINITRC}"
    "DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR=${OPENBOX_MANAGE_XSESSION_HOOK_DIR}"
    "DEBIAN_OPENBOX_FULLSCREEN=${OPENBOX_FULLSCREEN}"
    "DEBIAN_OPENBOX_FULLSCREEN_MATCH=${OPENBOX_FULLSCREEN_MATCH}"
    "DEBIAN_OPENBOX_FULLSCREEN_RETRIES=${OPENBOX_FULLSCREEN_RETRIES}"
    "DEBIAN_OPENBOX_FULLSCREEN_DELAY_MS=${OPENBOX_FULLSCREEN_DELAY_MS}"
    "DEBIAN_OPENBOX_FULLSCREEN_HELPER=${OPENBOX_FULLSCREEN_HELPER}"
    "DEBIAN_OPENBOX_RUNTIME_FACTS_PATH=${OPENBOX_RUNTIME_FACTS_PATH}"
    "DEBIAN_OPENBOX_INSTALL_PACKAGES=${OPENBOX_INSTALL_PACKAGES}"
    "DEBIAN_OPENBOX_PACKAGES=${OPENBOX_PACKAGES}"
    "DEBIAN_OPENBOX_SUDO_REEXEC=1"
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

  if [[ "${DEBIAN_OPENBOX_SUDO_REEXEC:-0}" = "1" ]]; then
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
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${PAGES_BASE_URL}/setup/cli/openbox" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because wget is unavailable."
  exit 1
}

resolve.defaults() {
  if [[ "${OPENBOX_ENABLE_SET}" -eq 0 ]]; then
    case "${FEATURE_MODE}" in
      disable) OPENBOX_ENABLE=0 ;;
      *) OPENBOX_ENABLE=1 ;;
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

  if [[ -r "${repo_root}/ansible/${OPENBOX_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    OPENBOX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${OPENBOX_PLAYBOOK_REL}"
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

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${OPENBOX_PLAYBOOK_REL}" "${OPENBOX_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.openbox.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${OPENBOX_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
openbox_enable: $(bool.yaml "${OPENBOX_ENABLE}")
openbox_mode: $(yaml.quote "${FEATURE_MODE}")
openbox_user: $(yaml.quote "${OPENBOX_USER}")
openbox_session_command: $(yaml.quote "${OPENBOX_SESSION_COMMAND}")
openbox_xinitrc_path: $(yaml.quote "${OPENBOX_XINITRC_PATH}")
openbox_xsession_hook_dir: $(yaml.quote "${OPENBOX_XSESSION_HOOK_DIR}")
openbox_manage_xinitrc: $(bool.yaml "${OPENBOX_MANAGE_XINITRC}")
openbox_manage_xsession_hook_dir: $(bool.yaml "${OPENBOX_MANAGE_XSESSION_HOOK_DIR}")
openbox_fullscreen: $(bool.yaml "${OPENBOX_FULLSCREEN}")
openbox_fullscreen_match: $(yaml.quote "${OPENBOX_FULLSCREEN_MATCH}")
openbox_fullscreen_retries: ${OPENBOX_FULLSCREEN_RETRIES}
openbox_fullscreen_delay_ms: ${OPENBOX_FULLSCREEN_DELAY_MS}
openbox_fullscreen_helper: $(yaml.quote "${OPENBOX_FULLSCREEN_HELPER}")
openbox_runtime_facts_path: $(yaml.quote "${OPENBOX_RUNTIME_FACTS_PATH}")
openbox_install_packages: $(bool.yaml "${OPENBOX_INSTALL_PACKAGES}")
openbox_packages: $(yaml.string.list "${OPENBOX_PACKAGES}")
EOF_VARS
  log "Prepared openbox extra-vars: ${OPENBOX_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Mode: ${FEATURE_MODE}"
  log "Openbox enabled: ${OPENBOX_ENABLE}"
  log "User: ${OPENBOX_USER}"
  log "Session command: ${OPENBOX_SESSION_COMMAND}"
  log "xinitrc: ${OPENBOX_XINITRC_PATH}"
  log "Hook dir: ${OPENBOX_XSESSION_HOOK_DIR}"
  log "Fullscreen: ${OPENBOX_FULLSCREEN}"
  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/openbox | bash"
}

run.openbox.feature() {
  write.openbox.extra.vars.file
  log "Running Debian Openbox feature..."
  run.feature.playbook "${OPENBOX_PLAYBOOK_PATH}" -e "@${OPENBOX_EXTRA_VARS_PATH}"
}

main() {
  reset.feature.tmp.cache
  source.release.common
  ensure.root.or.sudo.reexec "$@"
  require.debian.host
  require.root
  require.apt
  require.valid.mode
  resolve.defaults
  ensure.local.ansible

  run.preflight
  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    return 0
  fi

  prepare.feature.files
  run.openbox.feature
}

main "$@"
