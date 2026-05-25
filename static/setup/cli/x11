#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/x11
## Minimal Debian X11 setup runner.
## Local usage:
##   ./setup/cli/x11.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/x11 | bash

set -euo pipefail

log() { printf '[setup.cli.x11] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.x11][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.x11}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "cli/x11.yml"
)
X11_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
X11_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${X11_PLAYBOOK_REL}"
X11_EXTRA_VARS_PATH="${TMP_DIR}/x11.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_X11_MODE:-apply}}"
X11_ENABLE="${DEBIAN_X11_ENABLE:-}"
X11_INSTALL_PACKAGES="${DEBIAN_X11_INSTALL_PACKAGES:-1}"
X11_PACKAGES="${DEBIAN_X11_PACKAGES:-xserver-xorg xserver-xorg-legacy xinit x11-apps x11-xserver-utils x11-utils xauth dbus-x11 wmctrl}"
X11_RUNTIME_FACTS_PATH="${DEBIAN_X11_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/x11.yml}"
REFRESH="${REFRESH:-0}"
X11_ENABLE_SET=0

declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

if [[ -n "${DEBIAN_X11_ENABLE+x}" ]]; then
  X11_ENABLE_SET=1
fi

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
  # shellcheck source=/tmp/ansible/debian/cli.x11/release.common.sh
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
    "DEBIAN_X11_ENABLE=${X11_ENABLE}"
    "DEBIAN_X11_MODE=${FEATURE_MODE}"
    "DEBIAN_X11_INSTALL_PACKAGES=${X11_INSTALL_PACKAGES}"
    "DEBIAN_X11_PACKAGES=${X11_PACKAGES}"
    "DEBIAN_X11_RUNTIME_FACTS_PATH=${X11_RUNTIME_FACTS_PATH}"
    "DEBIAN_X11_SUDO_REEXEC=1"
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

  if [[ "${DEBIAN_X11_SUDO_REEXEC:-0}" = "1" ]]; then
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
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${PAGES_BASE_URL}/setup/cli/x11" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because wget is unavailable."
  exit 1
}

resolve.defaults() {
  if [[ "${X11_ENABLE_SET}" -eq 0 ]]; then
    case "${FEATURE_MODE}" in
      disable) X11_ENABLE=0 ;;
      *) X11_ENABLE=1 ;;
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

  if [[ -r "${repo_root}/ansible/${X11_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    X11_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${X11_PLAYBOOK_REL}"
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

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${X11_PLAYBOOK_REL}" "${X11_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.x11.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${X11_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
x11_enable: $(bool.yaml "${X11_ENABLE}")
x11_mode: $(yaml.quote "${FEATURE_MODE}")
x11_install_packages: $(bool.yaml "${X11_INSTALL_PACKAGES}")
x11_packages: $(yaml.string.list "${X11_PACKAGES}")
x11_runtime_facts_path: $(yaml.quote "${X11_RUNTIME_FACTS_PATH}")
EOF_VARS
  log "Prepared X11 extra-vars: ${X11_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Mode: ${FEATURE_MODE}"
  log "X11 enabled: ${X11_ENABLE}"
  log "Install X11 packages: ${X11_INSTALL_PACKAGES}"
  log "Packages: ${X11_PACKAGES}"
  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/x11 | bash"
}

run.x11.feature() {
  write.x11.extra.vars.file
  log "Running Debian X11 feature..."
  run.feature.playbook "${X11_PLAYBOOK_PATH}" -e "@${X11_EXTRA_VARS_PATH}"
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
  run.x11.feature
}

main "$@"
