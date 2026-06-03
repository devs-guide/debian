#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/codex.sh
## Manual Debian Node + Codex setup runner.
## Local usage:
##   ./setup/cli/codex.sh [preflight|apply]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/codex.sh | bash

set -euo pipefail

log() { printf '[setup.cli.codex] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.codex][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/cli.codex}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "cli/node.yml"
  "cli/codex.yml"
)
NODE_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
CODEX_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[1]}"
NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
CODEX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${CODEX_PLAYBOOK_REL}"
CLI_CODEX_EXTRA_VARS_PATH="${TMP_DIR}/cli.codex.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_CLI_CODEX_MODE:-apply}}"
NODE_NVM_VERSION="${DEBIAN_CLI_CODEX_NVM_VERSION:-v0.40.4}"
NODE_VERSION="${DEBIAN_CLI_CODEX_NODE_VERSION:-lts/*}"
NODE_INSTALL_SCOPE="${DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE:-shared}"
NODE_SHARED_NVM_DIR="${DEBIAN_CLI_CODEX_NODE_SHARED_NVM_DIR:-/usr/local/lib/nvm}"
NODE_NVM_DIR="${DEBIAN_CLI_CODEX_NODE_NVM_DIR:-}"
if [[ -z "${NODE_NVM_DIR}" ]]; then
  case "${NODE_INSTALL_SCOPE}" in
    shared) NODE_NVM_DIR="${NODE_SHARED_NVM_DIR}" ;;
    *) NODE_NVM_DIR="/root/.nvm" ;;
  esac
fi
NODE_NPM_POLICY="${DEBIAN_CLI_CODEX_NODE_NPM_POLICY:-bundled}"
NODE_NPM_VERSION="${DEBIAN_CLI_CODEX_NODE_NPM_VERSION:-}"
NODE_CREATE_SYSTEM_SYMLINKS="${DEBIAN_CLI_CODEX_NODE_CREATE_SYSTEM_SYMLINKS:-1}"
NODE_ENABLE_COREPACK="${DEBIAN_CLI_CODEX_NODE_ENABLE_COREPACK:-0}"
CODEX_NPM_PACKAGE="${DEBIAN_CLI_CODEX_PACKAGE:-@openai/codex}"
CODEX_VERSION="${DEBIAN_CLI_CODEX_VERSION:-latest}"
CODEX_INSTALL_DOCS_MCP="${DEBIAN_CLI_CODEX_INSTALL_DOCS_MCP:-1}"
CODEX_DOCS_MCP_NAME="${DEBIAN_CLI_CODEX_DOCS_MCP_NAME:-openaiDeveloperDocs}"
CODEX_DOCS_MCP_URL="${DEBIAN_CLI_CODEX_DOCS_MCP_URL:-https://developers.openai.com/mcp}"
FACTS_DIR="${DEBIAN_CLI_CODEX_FACTS_DIR:-/etc/ansible/debian/facts}"
CODEX_RUNTIME_FACTS_PATH="${DEBIAN_CLI_CODEX_RUNTIME_FACTS_PATH:-${FACTS_DIR}/cli.codex.yml}"
CODEX_SELF_URL="${DEBIAN_CLI_CODEX_SELF_URL:-${PAGES_BASE_URL}/setup/cli/codex.sh}"
CODEX_SUDO_REEXEC="${DEBIAN_CLI_CODEX_SUDO_REEXEC:-0}"
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
  # shellcheck source=/tmp/ansible/debian/cli.codex/release.common.sh
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
    preflight|apply) ;;
    *)
      log.error "Unsupported mode: ${FEATURE_MODE}"
      log.error "Use one of: preflight, apply"
      exit 1
      ;;
  esac
}

require.valid.install.scope() {
  case "${NODE_INSTALL_SCOPE}" in
    private|shared) ;;
    *)
      log.error "Unsupported Node install scope: ${NODE_INSTALL_SCOPE}"
      log.error "Use one of: private, shared"
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
    "DEBIAN_CLI_CODEX_MODE=${FEATURE_MODE}"
    "DEBIAN_CLI_CODEX_NVM_VERSION=${NODE_NVM_VERSION}"
    "DEBIAN_CLI_CODEX_NODE_VERSION=${NODE_VERSION}"
    "DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE=${NODE_INSTALL_SCOPE}"
    "DEBIAN_CLI_CODEX_NODE_SHARED_NVM_DIR=${NODE_SHARED_NVM_DIR}"
    "DEBIAN_CLI_CODEX_NODE_NVM_DIR=${NODE_NVM_DIR}"
    "DEBIAN_CLI_CODEX_NODE_NPM_POLICY=${NODE_NPM_POLICY}"
    "DEBIAN_CLI_CODEX_NODE_NPM_VERSION=${NODE_NPM_VERSION}"
    "DEBIAN_CLI_CODEX_NODE_CREATE_SYSTEM_SYMLINKS=${NODE_CREATE_SYSTEM_SYMLINKS}"
    "DEBIAN_CLI_CODEX_NODE_ENABLE_COREPACK=${NODE_ENABLE_COREPACK}"
    "DEBIAN_CLI_CODEX_PACKAGE=${CODEX_NPM_PACKAGE}"
    "DEBIAN_CLI_CODEX_VERSION=${CODEX_VERSION}"
    "DEBIAN_CLI_CODEX_INSTALL_DOCS_MCP=${CODEX_INSTALL_DOCS_MCP}"
    "DEBIAN_CLI_CODEX_DOCS_MCP_NAME=${CODEX_DOCS_MCP_NAME}"
    "DEBIAN_CLI_CODEX_DOCS_MCP_URL=${CODEX_DOCS_MCP_URL}"
    "DEBIAN_CLI_CODEX_FACTS_DIR=${FACTS_DIR}"
    "DEBIAN_CLI_CODEX_RUNTIME_FACTS_PATH=${CODEX_RUNTIME_FACTS_PATH}"
    "DEBIAN_CLI_CODEX_SELF_URL=${CODEX_SELF_URL}"
    "DEBIAN_CLI_CODEX_SUDO_REEXEC=1"
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

  if [[ "${CODEX_SUDO_REEXEC}" = "1" ]]; then
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
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${CODEX_SELF_URL}" "$@"
  fi

  if command -v curl >/dev/null 2>&1; then
    exec sudo -E env "${sudo_env[@]}" bash -c 'curl -fsSL "$1" | bash -s -- "${@:2}"' bash "${CODEX_SELF_URL}" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because neither wget nor curl is available."
  exit 1
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
  repo_root="$(cd "${script_dir}/../.." && pwd)"

  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ ! -r "${repo_root}/ansible/group_vars/${file}" ]]; then
      return 1
    fi
  done

  if [[ -r "${repo_root}/ansible/${NODE_PLAYBOOK_REL}" && -r "${repo_root}/ansible/${CODEX_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    NODE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NODE_PLAYBOOK_REL}"
    CODEX_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${CODEX_PLAYBOOK_REL}"
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

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${NODE_PLAYBOOK_REL}" "${NODE_PLAYBOOK_PATH}"
  fetch.feature.file "${PAGES_BASE_URL}/ansible/${CODEX_PLAYBOOK_REL}" "${CODEX_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.cli.codex.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${CLI_CODEX_EXTRA_VARS_PATH}" <<EOF
---
ansible_python_interpreter_managed: "/usr/bin/python3"
debian_runtime_facts_dir: $(yaml.quote "${FACTS_DIR}")
node_enable: true
node_nvm_version: $(yaml.quote "${NODE_NVM_VERSION}")
nvm_version: $(yaml.quote "${NODE_NVM_VERSION}")
node_install_scope: $(yaml.quote "${NODE_INSTALL_SCOPE}")
node_shared_nvm_dir: $(yaml.quote "${NODE_SHARED_NVM_DIR}")
node_nvm_dir: $(yaml.quote "${NODE_NVM_DIR}")
nvm_dir: $(yaml.quote "${NODE_NVM_DIR}")
node_version: $(yaml.quote "${NODE_VERSION}")
node_npm_policy: $(yaml.quote "${NODE_NPM_POLICY}")
node_npm_version: $(yaml.quote "${NODE_NPM_VERSION}")
node_create_system_symlinks: $(bool.yaml "${NODE_CREATE_SYSTEM_SYMLINKS}")
node_enable_corepack: $(bool.yaml "${NODE_ENABLE_COREPACK}")
codex_enable: true
codex_mode: $(yaml.quote "${FEATURE_MODE}")
codex_node_install_scope: $(yaml.quote "${NODE_INSTALL_SCOPE}")
codex_node_shared_nvm_dir: $(yaml.quote "${NODE_SHARED_NVM_DIR}")
codex_nvm_dir: $(yaml.quote "${NODE_NVM_DIR}")
codex_npm_package: $(yaml.quote "${CODEX_NPM_PACKAGE}")
codex_version: $(yaml.quote "${CODEX_VERSION}")
codex_install_docs_mcp: $(bool.yaml "${CODEX_INSTALL_DOCS_MCP}")
codex_docs_mcp_name: $(yaml.quote "${CODEX_DOCS_MCP_NAME}")
codex_docs_mcp_url: $(yaml.quote "${CODEX_DOCS_MCP_URL}")
codex_runtime_facts_path: $(yaml.quote "${CODEX_RUNTIME_FACTS_PATH}")
EOF
  log "Prepared CLI/Codex extra-vars: ${CLI_CODEX_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Feature mode: ${FEATURE_MODE}"
  log "Target runtime: Debian host"
  log "Desired Node version: ${NODE_VERSION}"
  log "Node install scope: ${NODE_INSTALL_SCOPE}"
  log "Node NVM dir: ${NODE_NVM_DIR}"
  log "Desired Codex package: ${CODEX_NPM_PACKAGE}"
  log "Desired Codex version: ${CODEX_VERSION}"
  log "OpenAI docs MCP bootstrap: ${CODEX_INSTALL_DOCS_MCP}"

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

  if command -v codex >/dev/null 2>&1; then
    log "Existing codex: $(codex --version 2>/dev/null)"
  else
    log "Existing codex: not installed"
  fi

  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/cli/codex.sh | bash"
}

run.cli.codex.feature() {
  write.cli.codex.extra.vars.file
  log "Running Debian Node feature..."
  run.feature.playbook "${NODE_PLAYBOOK_PATH}" -e "@${CLI_CODEX_EXTRA_VARS_PATH}"
  log "Running Debian Codex feature..."
  run.feature.playbook "${CODEX_PLAYBOOK_PATH}" -e "@${CLI_CODEX_EXTRA_VARS_PATH}"
}

main() {
  require.valid.mode
  require.valid.install.scope
  ensure.root.or.sudo.reexec "$@"
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host

  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    run.preflight
    exit 0
  fi

  ensure.local.ansible
  prepare.feature.files
  run.cli.codex.feature
}

main "$@"
