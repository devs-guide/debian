#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/node.sh
## Manual Debian Node setup runner.
## Local usage:
##   ./setup/cli/node.sh [preflight|apply|upgrade]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/node | bash

set -euo pipefail

log() { printf '[setup.cli.node] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.node][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.node}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
RELEASE_GROUP_VARS_FILE="${DEBIAN_NODE_RELEASE_GROUP_VARS_FILE:-}"
FEATURE_PLAYBOOKS=(
  "cli/node.yml"
)
NODE_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
NODE_EXTRA_VARS_PATH="${TMP_DIR}/cli.node.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_NODE_MODE:-apply}}"
NODE_VERSION="${DEBIAN_NODE_VERSION:-lts/*}"
NODE_NVM_VERSION="${DEBIAN_NODE_NVM_VERSION:-v0.40.4}"
NODE_NVM_DIR="${DEBIAN_NODE_NVM_DIR:-/root/.nvm}"
NODE_NPM_POLICY="${DEBIAN_NODE_NPM_POLICY:-bundled}"
NODE_NPM_VERSION="${DEBIAN_NODE_NPM_VERSION:-}"
NODE_GLOBAL_PACKAGES="${DEBIAN_NODE_GLOBAL_PACKAGES:-}"
NODE_CREATE_SYSTEM_SYMLINKS="${DEBIAN_NODE_CREATE_SYSTEM_SYMLINKS:-1}"
NODE_ENABLE_COREPACK="${DEBIAN_NODE_ENABLE_COREPACK:-0}"
FACTS_DIR="${DEBIAN_NODE_FACTS_DIR:-/etc/ansible/debian/facts}"
NODE_RUNTIME_FACTS_PATH="${DEBIAN_NODE_RUNTIME_FACTS_PATH:-${FACTS_DIR}/node.yml}"
REFRESH="${REFRESH:-0}"
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
  # shellcheck source=/tmp/ansible/debian/cli.node/release.common.sh
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

  read -r -a values <<< "${raw}"
  if ((${#values[@]} == 0)); then
    printf '[]'
    return 0
  fi

  printf '['
  for item in "${values[@]}"; do
    printf '%s, ' "$(yaml.quote "${item}")"
  done
  printf '\b\b]'
}

require.valid.mode() {
  case "${FEATURE_MODE}" in
    preflight|apply|upgrade) ;;
    *)
      log.error "Unsupported mode: ${FEATURE_MODE}"
      log.error "Use one of: preflight, apply, upgrade"
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

reset.feature.extra.vars.args() {
  FEATURE_GROUP_VARS_ARGS=()
  local file=""
  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ -f "${PLAYBOOK_GROUP_VARS_DIR}/${file}" ]]; then
      FEATURE_GROUP_VARS_ARGS+=(-e "@${PLAYBOOK_GROUP_VARS_DIR}/${file}")
    fi
  done
}

resolve.release.group.vars.file() {
  local codename=""

  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    RELEASE_GROUP_VARS_FILE="${RELEASE_GROUP_VARS_FILE##*/}"
    return
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi

  case "${codename}" in
    buster) RELEASE_GROUP_VARS_FILE="buster.yml" ;;
    trixie) RELEASE_GROUP_VARS_FILE="trixie.yml" ;;
    *) RELEASE_GROUP_VARS_FILE="" ;;
  esac
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

  if [[ -n "${RELEASE_GROUP_VARS_FILE}" && ! -r "${repo_root}/ansible/group_vars/${RELEASE_GROUP_VARS_FILE}" ]]; then
    RELEASE_GROUP_VARS_FILE=""
  fi

  if [[ -r "${repo_root}/ansible/${NODE_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
    if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
      GROUP_VARS_FILES+=("${RELEASE_GROUP_VARS_FILE}")
    fi
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

fetch.optional.feature.file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "${dest}")"
  if ! wget -qO "${dest}" "${url}"; then
    rm -f "${dest}"
    return 1
  fi
  if [[ ! -s "${dest}" ]]; then
    rm -f "${dest}"
    return 1
  fi
  return 0
}

prepare.feature.files() {
  local file=""

  resolve.release.group.vars.file

  if use.local.feature.files; then
    return
  fi

  mkdir -p "${PLAYBOOK_GROUP_VARS_DIR}"
  for file in all.yml debian.yml; do
    fetch.feature.file \
      "${PAGES_BASE_URL}/ansible/group_vars/${file}" \
      "${PLAYBOOK_GROUP_VARS_DIR}/${file}"
  done
  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    fetch.optional.feature.file \
      "${PAGES_BASE_URL}/ansible/group_vars/${RELEASE_GROUP_VARS_FILE}" \
      "${PLAYBOOK_GROUP_VARS_DIR}/${RELEASE_GROUP_VARS_FILE}" || true
    if [[ -f "${PLAYBOOK_GROUP_VARS_DIR}/${RELEASE_GROUP_VARS_FILE}" ]]; then
      GROUP_VARS_FILES+=("${RELEASE_GROUP_VARS_FILE}")
    else
      RELEASE_GROUP_VARS_FILE=""
    fi
  fi

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${NODE_PLAYBOOK_REL}" "${NODE_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.node.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${NODE_EXTRA_VARS_PATH}" <<EOF
---
ansible_python_interpreter_managed: "/usr/bin/python3"
node_enable: true
node_mode: $(yaml.quote "${FEATURE_MODE}")
node_version: $(yaml.quote "${NODE_VERSION}")
node_nvm_version: $(yaml.quote "${NODE_NVM_VERSION}")
nvm_version: $(yaml.quote "${NODE_NVM_VERSION}")
node_nvm_dir: $(yaml.quote "${NODE_NVM_DIR}")
nvm_dir: $(yaml.quote "${NODE_NVM_DIR}")
node_npm_policy: $(yaml.quote "${NODE_NPM_POLICY}")
node_npm_version: $(yaml.quote "${NODE_NPM_VERSION}")
node_global_packages: $(yaml.string.list "${NODE_GLOBAL_PACKAGES}")
node_create_system_symlinks: $(bool.yaml "${NODE_CREATE_SYSTEM_SYMLINKS}")
node_enable_corepack: $(bool.yaml "${NODE_ENABLE_COREPACK}")
node_runtime_facts_path: $(yaml.quote "${NODE_RUNTIME_FACTS_PATH}")
EOF
  log "Prepared Node extra-vars: ${NODE_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Feature mode: ${FEATURE_MODE}"
  log "Desired Node selector: ${NODE_VERSION}"
  log "NVM release: ${NODE_NVM_VERSION}"
  log "npm policy: ${NODE_NPM_POLICY}"

  if command -v node >/dev/null 2>&1; then
    log "Existing node: $(node --version 2>/dev/null)"
  else
    log "Existing node: not installed"
  fi

  if command -v npm >/dev/null 2>&1; then
    log "Existing npm: $(npm --version 2>/dev/null)"
  else
    log "Existing npm: not installed"
  fi

  if command -v npx >/dev/null 2>&1; then
    log "Existing npx: $(npx --version 2>/dev/null)"
  else
    log "Existing npx: not installed"
  fi

  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/node | bash"
}

run.node.feature() {
  write.node.extra.vars.file
  log "Running Debian Node feature..."
  run.feature.playbook "${NODE_PLAYBOOK_PATH}" -e "@${NODE_EXTRA_VARS_PATH}"
}

main() {
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host
  require.valid.mode

  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    run.preflight
    exit 0
  fi

  ensure.local.ansible
  prepare.feature.files
  run.node.feature
}

main "$@"
