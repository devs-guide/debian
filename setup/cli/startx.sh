#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/startx.sh
## Minimal Debian STARTX setup runner.
## Local usage:
##   ./setup/cli/startx.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/startx.sh | bash

set -euo pipefail

log() { printf '[setup.cli.startx] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.startx][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.startx}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
STARTX_SELF_URL="${DEBIAN_STARTX_SELF_URL:-${PAGES_BASE_URL}/setup/cli/startx.sh}"
STARTX_SUDO_REEXEC="${DEBIAN_STARTX_SUDO_REEXEC:-0}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "cli/startx.yml"
)
STARTX_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
STARTX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${STARTX_PLAYBOOK_REL}"
STARTX_EXTRA_VARS_PATH="${TMP_DIR}/startx.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_STARTX_MODE:-apply}}"
STARTX_ENABLE="${DEBIAN_STARTX_ENABLE:-}"
STARTX_USER="${DEBIAN_STARTX_USER:-app}"
STARTX_TTY="${DEBIAN_STARTX_TTY:-tty1}"
STARTX_DISPLAY="${DEBIAN_STARTX_DISPLAY:-:0}"
STARTX_INSTALL_PACKAGES="${DEBIAN_STARTX_INSTALL_PACKAGES:-1}"
STARTX_MANAGE_XWRAPPER="${DEBIAN_STARTX_MANAGE_XWRAPPER:-1}"
STARTX_ALLOWED_USERS="${DEBIAN_STARTX_ALLOWED_USERS:-console}"
STARTX_NEEDS_ROOT_RIGHTS="${DEBIAN_STARTX_NEEDS_ROOT_RIGHTS:-auto}"
STARTX_MANAGE_XINITRC="${DEBIAN_STARTX_MANAGE_XINITRC:-1}"
STARTX_MANAGE_WRAPPER="${DEBIAN_STARTX_MANAGE_WRAPPER:-1}"
STARTX_WRAPPER_PATH="${DEBIAN_STARTX_WRAPPER_PATH:-/usr/local/bin/kiosk-startx}"
STARTX_XINITRC_PATH="${DEBIAN_STARTX_XINITRC_PATH:-/home/app/.xinitrc}"
STARTX_XSESSION_HOOK_DIR="${DEBIAN_STARTX_XSESSION_HOOK_DIR:-/home/app/.config/debian/xsession.d}"
STARTX_OPENBOX_COMMAND="${DEBIAN_STARTX_OPENBOX_COMMAND:-/usr/bin/openbox-session}"
STARTX_SERVER_ARGS="${DEBIAN_STARTX_SERVER_ARGS:--nolisten tcp}"
STARTX_RUNTIME_FACTS_PATH="${DEBIAN_STARTX_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/startx.yml}"
FACTS_DIR="${DEBIAN_STARTX_FACTS_DIR:-/etc/ansible/debian/facts}"
REFRESH="${REFRESH:-0}"

STARTX_ENABLE_SET=0
if [[ -n "${DEBIAN_STARTX_ENABLE+x}" ]]; then
  STARTX_ENABLE_SET=1
fi

declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

reset.feature.tmp.cache() {
  case "${REFRESH,,}" in
    1|true|yes|y|on)
      log "REFRESH=1; clearing feature temp cache under ${TMP_DIR}"
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
  # shellcheck source=/tmp/ansible/debian/cli.startx/release.common.sh
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

collect.sudo.env.args() {
  local -n _out="$1"

  _out=(
    "DEBIAN_STARTX_ENABLE=${STARTX_ENABLE}"
    "DEBIAN_STARTX_MODE=${FEATURE_MODE}"
    "DEBIAN_STARTX_USER=${STARTX_USER}"
    "DEBIAN_STARTX_TTY=${STARTX_TTY}"
    "DEBIAN_STARTX_DISPLAY=${STARTX_DISPLAY}"
    "DEBIAN_STARTX_INSTALL_PACKAGES=${STARTX_INSTALL_PACKAGES}"
    "DEBIAN_STARTX_MANAGE_XWRAPPER=${STARTX_MANAGE_XWRAPPER}"
    "DEBIAN_STARTX_ALLOWED_USERS=${STARTX_ALLOWED_USERS}"
    "DEBIAN_STARTX_NEEDS_ROOT_RIGHTS=${STARTX_NEEDS_ROOT_RIGHTS}"
    "DEBIAN_STARTX_MANAGE_XINITRC=${STARTX_MANAGE_XINITRC}"
    "DEBIAN_STARTX_MANAGE_WRAPPER=${STARTX_MANAGE_WRAPPER}"
    "DEBIAN_STARTX_WRAPPER_PATH=${STARTX_WRAPPER_PATH}"
    "DEBIAN_STARTX_XINITRC_PATH=${STARTX_XINITRC_PATH}"
    "DEBIAN_STARTX_XSESSION_HOOK_DIR=${STARTX_XSESSION_HOOK_DIR}"
    "DEBIAN_STARTX_OPENBOX_COMMAND=${STARTX_OPENBOX_COMMAND}"
    "DEBIAN_STARTX_SERVER_ARGS=${STARTX_SERVER_ARGS}"
    "DEBIAN_STARTX_RUNTIME_FACTS_PATH=${STARTX_RUNTIME_FACTS_PATH}"
    "DEBIAN_STARTX_SELF_URL=${STARTX_SELF_URL}"
    "DEBIAN_STARTX_SUDO_REEXEC=1"
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

  if [[ "${STARTX_SUDO_REEXEC}" = "1" ]]; then
    log.error "sudo re-entry was requested but the script is still not root."
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
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${STARTX_SELF_URL}" "$@"
  fi

  if command -v curl >/dev/null 2>&1; then
    exec sudo -E env "${sudo_env[@]}" bash -c 'curl -fsSL "$1" | bash -s -- "${@:2}"' bash "${STARTX_SELF_URL}" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because neither wget nor curl is available."
  exit 1
}

require.debian.host() {
  if [[ ! -f /etc/debian_version ]]; then
    log.error "This feature runner expects a Debian host."
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

resolve.defaults() {
  if [[ "${STARTX_ENABLE_SET}" -eq 0 ]]; then
    case "${FEATURE_MODE}" in
      disable) STARTX_ENABLE=0 ;;
      *) STARTX_ENABLE=1 ;;
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

  if [[ -r "${repo_root}/ansible/${STARTX_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    STARTX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${STARTX_PLAYBOOK_REL}"
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

prepare.feature.files() {
  if use.local.feature.files; then
    return
  fi

  mkdir -p "${PLAYBOOK_GROUP_VARS_DIR}"
  for file in "${GROUP_VARS_FILES[@]}"; do
    fetch.feature.file "${PAGES_BASE_URL}/ansible/group_vars/${file}" "${PLAYBOOK_GROUP_VARS_DIR}/${file}"
  done

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${STARTX_PLAYBOOK_REL}" "${STARTX_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.startx.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${STARTX_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
startx_enable: $(bool.yaml "${STARTX_ENABLE}")
startx_mode: $(yaml.quote "${FEATURE_MODE}")
startx_user: $(yaml.quote "${STARTX_USER}")
startx_tty: $(yaml.quote "${STARTX_TTY}")
startx_display: $(yaml.quote "${STARTX_DISPLAY}")
startx_install_packages: $(bool.yaml "${STARTX_INSTALL_PACKAGES}")
startx_manage_xwrapper: $(bool.yaml "${STARTX_MANAGE_XWRAPPER}")
startx_allowed_users: $(yaml.quote "${STARTX_ALLOWED_USERS}")
startx_needs_root_rights: $(yaml.quote "${STARTX_NEEDS_ROOT_RIGHTS}")
startx_manage_xinitrc: $(bool.yaml "${STARTX_MANAGE_XINITRC}")
startx_manage_wrapper: $(bool.yaml "${STARTX_MANAGE_WRAPPER}")
startx_wrapper_path: $(yaml.quote "${STARTX_WRAPPER_PATH}")
startx_xinitrc_path: $(yaml.quote "${STARTX_XINITRC_PATH}")
startx_xsession_hook_dir: $(yaml.quote "${STARTX_XSESSION_HOOK_DIR}")
startx_openbox_command: $(yaml.quote "${STARTX_OPENBOX_COMMAND}")
startx_server_args: $(yaml.quote "${STARTX_SERVER_ARGS}")
startx_runtime_facts_path: $(yaml.quote "${STARTX_RUNTIME_FACTS_PATH}")
EOF_VARS
  log "Prepared STARTX extra-vars: ${STARTX_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Feature mode: ${FEATURE_MODE}"
  log "X user: ${STARTX_USER}"
  log "TTY: ${STARTX_TTY}"
  log "Display: ${STARTX_DISPLAY}"
  log "Install packages: ${STARTX_INSTALL_PACKAGES}"
  log "Manage Xwrapper: ${STARTX_MANAGE_XWRAPPER}"
  log "Manage xinitrc: ${STARTX_MANAGE_XINITRC}"
  log "Manage wrapper: ${STARTX_MANAGE_WRAPPER}"
  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/startx.sh | bash"
}

run.startx.feature() {
  write.startx.extra.vars.file
  log "Running Debian STARTX feature..."
  run.feature.playbook "${STARTX_PLAYBOOK_PATH}" -e "@${STARTX_EXTRA_VARS_PATH}"
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

  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    run.preflight
    exit 0
  fi

  prepare.feature.files
  run.startx.feature
}

main "$@"
