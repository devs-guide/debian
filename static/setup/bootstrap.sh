#!/usr/bin/env bash
# Published path:
# wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash

set -euo pipefail

log() { printf '[debian.bootstrap] %s\n' "$*" >&2; }
log.error() { printf '[debian.bootstrap][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/bootstrap}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
RELEASE_GROUP_VARS_FILE="${DEBIAN_RELEASE_GROUP_VARS_FILE:-}"
BOOTSTRAP_SELF_URL="${DEBIAN_BOOTSTRAP_SELF_URL:-${PAGES_BASE_URL}/setup/bootstrap.sh}"
BOOTSTRAP_SUDO_REEXEC="${DEBIAN_BOOTSTRAP_SUDO_REEXEC:-0}"
REFRESH="${REFRESH:-0}"

sha256.file() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
    return 0
  fi

  return 1
}

log.bootstrap.entry.identity() {
  local source_path="${BASH_SOURCE[0]:-stdin}"
  local source_hash=""

  if [[ -r "${source_path}" ]]; then
    source_hash="$(sha256.file "${source_path}" 2>/dev/null || true)"
  fi

  log "Bootstrap entry published path: ${PAGES_BASE_URL}/setup/bootstrap.sh"
  log "Bootstrap entry source path: ${source_path}"
  if [[ -n "${source_hash}" ]]; then
    log "Bootstrap entry sha256: ${source_hash}"
  fi
}

reset.bootstrap.tmp.cache() {
  case "${REFRESH,,}" in
    1|true|yes|y|on)
      log "REFRESH=1; clearing bootstrap temp cache under ${TMP_ROOT_DIR}"
      rm -rf "${TMP_DIR}" "${TMP_ROOT_DIR}"
      ;;
  esac
}

source.release.common() {
  local script_dir=""

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -r "${script_dir}/${COMMON_HELPER_NAME}" ]]; then
    COMMON_HELPER_PATH="${script_dir}/${COMMON_HELPER_NAME}"
    # shellcheck source=setup/release.common.sh
    source "${COMMON_HELPER_PATH}"
  else
    mkdir -p "${TMP_DIR}"
    log "Fetching shared helper: ${COMMON_HELPER_URL}"
    if ! wget -qO "${COMMON_HELPER_PATH}" "${COMMON_HELPER_URL}"; then
      log.error "Failed to fetch ${COMMON_HELPER_URL}"
      exit 1
    fi
    # shellcheck source=/tmp/ansible/debian/bootstrap/release.common.sh
    source "${COMMON_HELPER_PATH}"
  fi

  if declare -F log.runtime.helper.identity >/dev/null 2>&1; then
    log.runtime.helper.identity
  fi
}

detect.release.groupvars() {
  resolve.release.groupvars.file
}

collect.sudo.env.args() {
  local -n _out="$1"

  _out=(
    "DEBIAN_RELEASE_GROUP_VARS_FILE=${RELEASE_GROUP_VARS_FILE}"
    "DEBIAN_BOOTSTRAP_SELF_URL=${BOOTSTRAP_SELF_URL}"
    "DEBIAN_BOOTSTRAP_SUDO_REEXEC=1"
    "PAGES_BASE_URL=${PAGES_BASE_URL}"
    "TMP_ROOT_DIR=${TMP_ROOT_DIR}"
    "TMP_DIR=${TMP_DIR}"
    "REFRESH=${REFRESH}"
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

  if [[ "${BOOTSTRAP_SUDO_REEXEC}" = "1" ]]; then
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
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${BOOTSTRAP_SELF_URL}" "$@"
  fi

  if command -v curl >/dev/null 2>&1; then
    exec sudo -E env "${sudo_env[@]}" bash -c 'curl -fsSL "$1" | bash -s -- "${@:2}"' bash "${BOOTSTRAP_SELF_URL}" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because neither wget nor curl is available."
  exit 1
}

use.local.runtime.files() {
  local script_dir repo_root

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"

  if [[ -r "${repo_root}/ansible/install.playbooks.txt" && -r "${repo_root}/ansible/group_vars/all.yml" ]]; then
    use.local.runtime.tree "${repo_root}"
    log "Using local runtime tree from ${repo_root}"
    return 0
  fi

  return 1
}

main() {
  log.bootstrap.entry.identity
  reset.bootstrap.tmp.cache
  source.release.common
  ensure.root.or.sudo.reexec "$@"
  require.root
  require.apt
  require.debian
  detect.release.groupvars
  resolve.controller.python.policy

  if ! use.local.runtime.files; then
    use.remote.runtime.tree
    fetch.groupvars
    fetch.playlist
  fi

  ensure.managed.ansible
  write.bootstrap.selection.marker
  run.playlist
  log "Bootstrap finished successfully."
}

main "$@"
