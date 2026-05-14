#!/usr/bin/env bash

set -euo pipefail

log() { printf '[debian.bootstrap] %s\n' "$*" >&2; }
log.error() { printf '[debian.bootstrap][error] %s\n' "$*" >&2; }

TMP_DIR="${TMP_DIR:-/tmp/devsguide-debian-bootstrap}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
RELEASE_GROUP_VARS_FILE="${DEBIAN_RELEASE_GROUP_VARS_FILE:-}"

source.release.common() {
  local script_dir=""

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -r "${script_dir}/${COMMON_HELPER_NAME}" ]]; then
    # shellcheck source=setup/release.common.sh
    source "${script_dir}/${COMMON_HELPER_NAME}"
    return
  fi

  mkdir -p "${TMP_DIR}"
  log "Fetching shared helper: ${COMMON_HELPER_URL}"
  if ! wget -qO "${COMMON_HELPER_PATH}" "${COMMON_HELPER_URL}"; then
    log.error "Failed to fetch ${COMMON_HELPER_URL}"
    exit 1
  fi
  # shellcheck source=/tmp/devsguide-debian-bootstrap/release.common.sh
  source "${COMMON_HELPER_PATH}"
}

detect.release.groupvars() {
  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    return
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ -n "${VERSION_CODENAME:-}" ]]; then
      RELEASE_GROUP_VARS_FILE="${VERSION_CODENAME}.yml"
    fi
  fi
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
  source.release.common
  require.root
  require.apt
  require.debian
  detect.release.groupvars

  if ! use.local.runtime.files; then
    use.remote.runtime.tree
    fetch.groupvars
    fetch.playlist
  fi

  ensure.managed.ansible
  run.playlist
  log "Bootstrap finished successfully."
}

main "$@"
