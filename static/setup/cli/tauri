#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/tauri.sh
## Manual Debian Tauri runtime/build setup runner.
## Local usage:
##   ./setup/cli/tauri.sh [preflight|apply|upgrade]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | bash

set -euo pipefail

log() { printf '[setup.cli.tauri] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.tauri][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.tauri}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
RELEASE_GROUP_VARS_FILE="${DEBIAN_CLI_TAURI_RELEASE_GROUP_VARS_FILE:-}"
FEATURE_PLAYBOOKS=(
  "cli/node.yml"
  "cli/tauri.yml"
)
NODE_PLAYBOOK_REL="cli/node.yml"
TAURI_PLAYBOOK_REL="cli/tauri.yml"
NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
TAURI_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${TAURI_PLAYBOOK_REL}"
TAURI_EXTRA_VARS_PATH="${TMP_DIR}/cli.tauri.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_CLI_TAURI_MODE:-apply}}"
TAURI_PROFILE="${DEBIAN_CLI_TAURI_PROFILE:-runtime}"
TAURI_INSTALL_RUNTIME="${DEBIAN_CLI_TAURI_INSTALL_RUNTIME:-}"
TAURI_INSTALL_BUILD_DEPS="${DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS:-}"
TAURI_INSTALL_NODE="${DEBIAN_CLI_TAURI_INSTALL_NODE:-}"
TAURI_NODE_VERSION="${DEBIAN_CLI_TAURI_NODE_VERSION:-lts/*}"
TAURI_ENABLE_COREPACK="${DEBIAN_CLI_TAURI_ENABLE_COREPACK:-0}"
TAURI_INSTALL_RUST="${DEBIAN_CLI_TAURI_INSTALL_RUST:-}"
TAURI_RUST_TOOLCHAIN="${DEBIAN_CLI_TAURI_RUST_TOOLCHAIN:-stable}"
TAURI_RUST_USER="${DEBIAN_CLI_TAURI_RUST_USER:-root}"
TAURI_INSTALL_CLI="${DEBIAN_CLI_TAURI_INSTALL_CLI:-}"
TAURI_CLI_METHOD="${DEBIAN_CLI_TAURI_CLI_METHOD:-npm}"
TAURI_NPM_PACKAGE="${DEBIAN_CLI_TAURI_NPM_PACKAGE:-@tauri-apps/cli}"
TAURI_NPM_VERSION="${DEBIAN_CLI_TAURI_NPM_VERSION:-latest}"
TAURI_INSTALL_APPIMAGE_TOOLS="${DEBIAN_CLI_TAURI_INSTALL_APPIMAGE_TOOLS:-0}"
TAURI_INSTALL_TEST_TOOLS="${DEBIAN_CLI_TAURI_INSTALL_TEST_TOOLS:-0}"
FACTS_DIR="${DEBIAN_CLI_TAURI_FACTS_DIR:-/etc/ansible/debian/facts}"
TAURI_RUNTIME_FACTS_PATH="${DEBIAN_CLI_TAURI_RUNTIME_FACTS_PATH:-${FACTS_DIR}/cli.tauri.yml}"
REFRESH="${REFRESH:-0}"
TAURI_INSTALL_RUNTIME_SET=0
TAURI_INSTALL_BUILD_DEPS_SET=0
TAURI_INSTALL_NODE_SET=0
TAURI_INSTALL_RUST_SET=0
TAURI_INSTALL_CLI_SET=0
declare -a FEATURE_GROUP_VARS_ARGS
FEATURE_GROUP_VARS_ARGS=()

if [[ -n "${DEBIAN_CLI_TAURI_INSTALL_RUNTIME+x}" ]]; then
  TAURI_INSTALL_RUNTIME_SET=1
fi
if [[ -n "${DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS+x}" ]]; then
  TAURI_INSTALL_BUILD_DEPS_SET=1
fi
if [[ -n "${DEBIAN_CLI_TAURI_INSTALL_NODE+x}" ]]; then
  TAURI_INSTALL_NODE_SET=1
fi
if [[ -n "${DEBIAN_CLI_TAURI_INSTALL_RUST+x}" ]]; then
  TAURI_INSTALL_RUST_SET=1
fi
if [[ -n "${DEBIAN_CLI_TAURI_INSTALL_CLI+x}" ]]; then
  TAURI_INSTALL_CLI_SET=1
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
  # shellcheck source=/tmp/ansible/debian/cli.tauri/release.common.sh
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
    preflight|apply|upgrade) ;;
    *)
      log.error "Unsupported mode: ${FEATURE_MODE}"
      log.error "Use one of: preflight, apply, upgrade"
      exit 1
      ;;
  esac
}

require.valid.profile() {
  case "${TAURI_PROFILE}" in
    runtime|build) ;;
    *)
      log.error "Unsupported profile: ${TAURI_PROFILE}"
      log.error "Use one of: runtime, build"
      exit 1
      ;;
  esac
}

require.valid.cli.method() {
  case "${TAURI_CLI_METHOD}" in
    npm|cargo|none) ;;
    *)
      log.error "Unsupported CLI install method: ${TAURI_CLI_METHOD}"
      log.error "Use one of: npm, cargo, none"
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

resolve.profile.defaults() {
  case "${TAURI_PROFILE}" in
    runtime)
      if [[ "${TAURI_INSTALL_RUNTIME_SET}" -eq 0 ]]; then TAURI_INSTALL_RUNTIME=1; fi
      if [[ "${TAURI_INSTALL_BUILD_DEPS_SET}" -eq 0 ]]; then TAURI_INSTALL_BUILD_DEPS=0; fi
      if [[ "${TAURI_INSTALL_NODE_SET}" -eq 0 ]]; then TAURI_INSTALL_NODE=0; fi
      if [[ "${TAURI_INSTALL_RUST_SET}" -eq 0 ]]; then TAURI_INSTALL_RUST=0; fi
      if [[ "${TAURI_INSTALL_CLI_SET}" -eq 0 ]]; then TAURI_INSTALL_CLI=0; fi
      ;;
    build)
      if [[ "${TAURI_INSTALL_RUNTIME_SET}" -eq 0 ]]; then TAURI_INSTALL_RUNTIME=1; fi
      if [[ "${TAURI_INSTALL_BUILD_DEPS_SET}" -eq 0 ]]; then TAURI_INSTALL_BUILD_DEPS=1; fi
      if [[ "${TAURI_INSTALL_NODE_SET}" -eq 0 ]]; then TAURI_INSTALL_NODE=1; fi
      if [[ "${TAURI_INSTALL_RUST_SET}" -eq 0 ]]; then TAURI_INSTALL_RUST=1; fi
      if [[ "${TAURI_INSTALL_CLI_SET}" -eq 0 ]]; then TAURI_INSTALL_CLI=1; fi
      ;;
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

  if [[ ! -r "${repo_root}/ansible/${TAURI_PLAYBOOK_REL}" ]]; then
    return 1
  fi
  if is.true "${TAURI_INSTALL_NODE}" && [[ "${FEATURE_MODE}" != "preflight" ]] && [[ ! -r "${repo_root}/ansible/${NODE_PLAYBOOK_REL}" ]]; then
    return 1
  fi

  PLAYBOOK_ROOT="${repo_root}/ansible"
  PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
  NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
  TAURI_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${TAURI_PLAYBOOK_REL}"
  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    GROUP_VARS_FILES+=("${RELEASE_GROUP_VARS_FILE}")
  fi
  reset.feature.extra.vars.args
  log "Using local feature files from ${repo_root}"
  return 0
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

  if is.true "${TAURI_INSTALL_NODE}" && [[ "${FEATURE_MODE}" != "preflight" ]]; then
    fetch.feature.file "${PAGES_BASE_URL}/ansible/${NODE_PLAYBOOK_REL}" "${NODE_PLAYBOOK_PATH}"
  fi
  fetch.feature.file "${PAGES_BASE_URL}/ansible/${TAURI_PLAYBOOK_REL}" "${TAURI_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.tauri.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${TAURI_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
tauri_enable: true
tauri_mode: $(yaml.quote "${FEATURE_MODE}")
tauri_profile: $(yaml.quote "${TAURI_PROFILE}")
tauri_install_runtime: $(bool.yaml "${TAURI_INSTALL_RUNTIME}")
tauri_install_build_deps: $(bool.yaml "${TAURI_INSTALL_BUILD_DEPS}")
tauri_install_node: $(bool.yaml "${TAURI_INSTALL_NODE}")
tauri_install_rust: $(bool.yaml "${TAURI_INSTALL_RUST}")
tauri_rust_toolchain: $(yaml.quote "${TAURI_RUST_TOOLCHAIN}")
tauri_rust_user: $(yaml.quote "${TAURI_RUST_USER}")
tauri_install_cli: $(bool.yaml "${TAURI_INSTALL_CLI}")
tauri_cli_method: $(yaml.quote "${TAURI_CLI_METHOD}")
tauri_npm_package: $(yaml.quote "${TAURI_NPM_PACKAGE}")
tauri_npm_version: $(yaml.quote "${TAURI_NPM_VERSION}")
tauri_enable_corepack: $(bool.yaml "${TAURI_ENABLE_COREPACK}")
tauri_install_appimage_tools: $(bool.yaml "${TAURI_INSTALL_APPIMAGE_TOOLS}")
tauri_install_test_tools: $(bool.yaml "${TAURI_INSTALL_TEST_TOOLS}")
tauri_runtime_facts_path: $(yaml.quote "${TAURI_RUNTIME_FACTS_PATH}")
node_enable: true
node_mode: "apply"
node_version: $(yaml.quote "${TAURI_NODE_VERSION}")
node_enable_corepack: $(bool.yaml "${TAURI_ENABLE_COREPACK}")
node_create_system_symlinks: true
EOF_VARS
  log "Prepared CLI/Tauri extra-vars: ${TAURI_EXTRA_VARS_PATH}"
}

run.tauri.feature() {
  write.tauri.extra.vars.file
  if is.true "${TAURI_INSTALL_NODE}" && [[ "${FEATURE_MODE}" != "preflight" ]]; then
    log "Running Debian Node feature for Tauri toolchain..."
    run.feature.playbook "${NODE_PLAYBOOK_PATH}" -e "@${TAURI_EXTRA_VARS_PATH}"
  fi
  log "Running Debian Tauri feature..."
  run.feature.playbook "${TAURI_PLAYBOOK_PATH}" -e "@${TAURI_EXTRA_VARS_PATH}"
}

main() {
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host
  require.valid.mode
  require.valid.profile
  resolve.profile.defaults
  require.valid.cli.method

  log "Feature mode: ${FEATURE_MODE}"
  log "Tauri profile: ${TAURI_PROFILE}"
  log "Install runtime libs: ${TAURI_INSTALL_RUNTIME}"
  log "Install build deps: ${TAURI_INSTALL_BUILD_DEPS}"
  log "Install Node playbook: ${TAURI_INSTALL_NODE}"
  log "Install Rust: ${TAURI_INSTALL_RUST}"
  log "Install Tauri CLI: ${TAURI_INSTALL_CLI}"

  ensure.local.ansible
  prepare.feature.files
  run.tauri.feature
}

main "$@"
