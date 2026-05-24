#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/autologin.sh
## Manual Debian autologin setup runner.
## Local usage:
##   ./setup/autologin.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/autologin | bash

set -euo pipefail

log() { printf '[setup.autologin] %s\n' "$*" >&2; }
log.error() { printf '[setup.autologin][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/autologin}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "autologin.yml"
)
AUTOLOGIN_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
AUTOLOGIN_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${AUTOLOGIN_PLAYBOOK_REL}"
AUTOLOGIN_EXTRA_VARS_PATH="${TMP_DIR}/autologin.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_AUTOLOGIN_MODE:-apply}}"
AUTOLOGIN_ENABLE="${DEBIAN_AUTOLOGIN_ENABLE:-}"
AUTOLOGIN_USER="${DEBIAN_AUTOLOGIN_USER:-app}"
AUTOLOGIN_TTY="${DEBIAN_AUTOLOGIN_TTY:-tty1}"
AUTOLOGIN_TERM="${DEBIAN_AUTOLOGIN_TERM:-linux}"
AUTOLOGIN_NORESET="${DEBIAN_AUTOLOGIN_NORESET:-1}"
AUTOLOGIN_NOCLEAR="${DEBIAN_AUTOLOGIN_NOCLEAR:-1}"
AUTOLOGIN_ACTION="${DEBIAN_AUTOLOGIN_ACTION:-shell}"
AUTOLOGIN_COMMAND="${DEBIAN_AUTOLOGIN_COMMAND:-}"
AUTOLOGIN_VALIDATION_BANNER="${DEBIAN_AUTOLOGIN_VALIDATION_BANNER:-1}"
AUTOLOGIN_MARKER_ENABLE="${DEBIAN_AUTOLOGIN_MARKER_ENABLE:-1}"
AUTOLOGIN_MARKER_PATH="${DEBIAN_AUTOLOGIN_MARKER_PATH:-/home/${AUTOLOGIN_USER}/.cache/autologin-${AUTOLOGIN_TTY}.ok}"
FACTS_DIR="${DEBIAN_AUTOLOGIN_FACTS_DIR:-/etc/ansible/debian/facts}"
AUTOLOGIN_RUNTIME_FACTS_PATH="${DEBIAN_AUTOLOGIN_RUNTIME_FACTS_PATH:-${FACTS_DIR}/autologin.yml}"
REFRESH="${REFRESH:-0}"
AUTOLOGIN_ENABLE_SET=0
declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

if [[ -n "${DEBIAN_AUTOLOGIN_ENABLE+x}" ]]; then
  AUTOLOGIN_ENABLE_SET=1
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
  # shellcheck source=/tmp/ansible/debian/autologin/release.common.sh
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

require.debian.host() {
  if [[ ! -f /etc/debian_version ]]; then
    log.error "This feature runner expects a Debian host."
    exit 1
  fi
}

resolve.autologin.defaults() {
  if [[ "${AUTOLOGIN_ENABLE_SET}" -eq 0 ]]; then
    case "${FEATURE_MODE}" in
      disable) AUTOLOGIN_ENABLE=0 ;;
      *) AUTOLOGIN_ENABLE=1 ;;
    esac
  fi
}

reset.feature.extra.vars.args() {
  FEATURE_GROUP_VARS_ARGS=()
  local file=""
  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ -f "${PLAYBOOK_GROUP_VARS_DIR}/${file}" ]]; then
      FEATURE_GROUP_VARS_ARGS+=(-e "@${PLAYBOOK_GROUP_VARS_DIR}/${file}")
    fi
  done
}

use.local.feature.files() {
  local script_dir repo_root file

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"

  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ ! -r "${repo_root}/ansible/group_vars/${file}" ]]; then
      return 1
    fi
  done

  if [[ -r "${repo_root}/ansible/${AUTOLOGIN_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    AUTOLOGIN_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${AUTOLOGIN_PLAYBOOK_REL}"
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
  local file=""

  if use.local.feature.files; then
    return
  fi

  mkdir -p "${PLAYBOOK_GROUP_VARS_DIR}"
  for file in "${GROUP_VARS_FILES[@]}"; do
    fetch.feature.file \
      "${PAGES_BASE_URL}/ansible/group_vars/${file}" \
      "${PLAYBOOK_GROUP_VARS_DIR}/${file}"
  done

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${AUTOLOGIN_PLAYBOOK_REL}" "${AUTOLOGIN_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.autologin.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${AUTOLOGIN_EXTRA_VARS_PATH}" <<EOF
---
ansible_python_interpreter_managed: "/usr/bin/python3"
autologin_enable: $(bool.yaml "${AUTOLOGIN_ENABLE}")
autologin_mode: $(yaml.quote "${FEATURE_MODE}")
autologin_user: $(yaml.quote "${AUTOLOGIN_USER}")
autologin_tty: $(yaml.quote "${AUTOLOGIN_TTY}")
autologin_term: $(yaml.quote "${AUTOLOGIN_TERM}")
autologin_noreset: $(bool.yaml "${AUTOLOGIN_NORESET}")
autologin_noclear: $(bool.yaml "${AUTOLOGIN_NOCLEAR}")
autologin_action: $(yaml.quote "${AUTOLOGIN_ACTION}")
autologin_command: $(yaml.quote "${AUTOLOGIN_COMMAND}")
autologin_validation_banner: $(bool.yaml "${AUTOLOGIN_VALIDATION_BANNER}")
autologin_marker_enable: $(bool.yaml "${AUTOLOGIN_MARKER_ENABLE}")
autologin_marker_path: $(yaml.quote "${AUTOLOGIN_MARKER_PATH}")
autologin_runtime_facts_path: $(yaml.quote "${AUTOLOGIN_RUNTIME_FACTS_PATH}")
EOF
  log "Prepared autologin extra-vars: ${AUTOLOGIN_EXTRA_VARS_PATH}"
}

run.autologin.feature() {
  write.autologin.extra.vars.file
  log "Running Debian autologin feature..."
  run.feature.playbook "${AUTOLOGIN_PLAYBOOK_PATH}" -e "@${AUTOLOGIN_EXTRA_VARS_PATH}"
}

main() {
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host
  require.valid.mode
  resolve.autologin.defaults

  log "Feature mode: ${FEATURE_MODE}"
  log "Autologin enabled: ${AUTOLOGIN_ENABLE}"
  log "Autologin user: ${AUTOLOGIN_USER}"
  log "Autologin tty: ${AUTOLOGIN_TTY}"
  log "Autologin action: ${AUTOLOGIN_ACTION}"
  log "Autologin marker path: ${AUTOLOGIN_MARKER_PATH}"

  ensure.local.ansible
  prepare.feature.files
  run.autologin.feature
}

main "$@"
