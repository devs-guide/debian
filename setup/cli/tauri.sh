#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/tauri.sh
## Manual Debian Tauri runtime/build setup runner.
## Local usage:
##   ./setup/cli/tauri.sh [preflight|apply|upgrade]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | bash
##
## IMPORTANT:
## Do not put DEBIAN_CLI_TAURI_* assignments before wget in a wget|bash pipeline.
## That scopes the variables to wget, not to the downloaded script.
##
## Safe multi-line usage:
##   export DEBIAN_CLI_TAURI_PROFILE=build
##   export DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1
##   export DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1
##   export DEBIAN_CLI_TAURI_INSTALL_NODE=1
##   export DEBIAN_CLI_TAURI_INSTALL_RUST=1
##   export DEBIAN_CLI_TAURI_INSTALL_CLI=1
##   export DEBIAN_CLI_TAURI_CLI_METHOD=npm
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | bash
##
## Correct one-liner usage:
##   env DEBIAN_CLI_TAURI_PROFILE=build DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 DEBIAN_CLI_TAURI_INSTALL_NODE=1 DEBIAN_CLI_TAURI_INSTALL_RUST=1 DEBIAN_CLI_TAURI_INSTALL_CLI=1 DEBIAN_CLI_TAURI_CLI_METHOD=npm bash -c 'wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | bash'
##
## Alternative right-side pipe usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | env DEBIAN_CLI_TAURI_PROFILE=build DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 DEBIAN_CLI_TAURI_INSTALL_NODE=1 DEBIAN_CLI_TAURI_INSTALL_RUST=1 DEBIAN_CLI_TAURI_INSTALL_CLI=1 DEBIAN_CLI_TAURI_CLI_METHOD=npm bash


## BUILD ENV:
## 
# env DEBIAN_CLI_TAURI_PROFILE=build DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 DEBIAN_CLI_TAURI_INSTALL_NODE=1 DEBIAN_CLI_TAURI_INSTALL_RUST=1 DEBIAN_CLI_TAURI_RUST_USER="$(id -un)" DEBIAN_CLI_TAURI_INSTALL_CLI=1 DEBIAN_CLI_TAURI_CLI_METHOD=npm bash -c 'wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | bash'
##

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
TAURI_SELF_URL="${DEBIAN_CLI_TAURI_SELF_URL:-${PAGES_BASE_URL}/setup/cli/tauri}"
TAURI_SUDO_REEXEC="${DEBIAN_CLI_TAURI_SUDO_REEXEC:-0}"
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
TAURI_NODE_INSTALL_SCOPE="${DEBIAN_CLI_TAURI_NODE_INSTALL_SCOPE:-shared}"
TAURI_NODE_SHARED_NVM_DIR="${DEBIAN_CLI_TAURI_NODE_SHARED_NVM_DIR:-/usr/local/lib/nvm}"
TAURI_NODE_NVM_DIR="${DEBIAN_CLI_TAURI_NODE_NVM_DIR:-}"
if [[ -z "${TAURI_NODE_NVM_DIR}" ]]; then
  case "${TAURI_NODE_INSTALL_SCOPE}" in
    shared) TAURI_NODE_NVM_DIR="${TAURI_NODE_SHARED_NVM_DIR}" ;;
    *) TAURI_NODE_NVM_DIR="/root/.nvm" ;;
  esac
fi
TAURI_NODE_VERSION="${DEBIAN_CLI_TAURI_NODE_VERSION:-lts/*}"
TAURI_NODE_MIN_MAJOR="${DEBIAN_CLI_TAURI_NODE_MIN_MAJOR:-20}"
TAURI_NPM_MIN_MAJOR="${DEBIAN_CLI_TAURI_NPM_MIN_MAJOR:-9}"
TAURI_INSTALL_NODE_REQUESTED="${TAURI_INSTALL_NODE:-}"
TAURI_INSTALL_NODE_EFFECTIVE="${TAURI_INSTALL_NODE:-}"
TAURI_NODE_CURRENT_VERSION="missing"
TAURI_NPM_CURRENT_VERSION="missing"
TAURI_NODE_CURRENT_PATH="missing"
TAURI_NODE_CURRENT_REALPATH="missing"
TAURI_NPM_CURRENT_PATH="missing"
TAURI_NPM_CURRENT_REALPATH="missing"
TAURI_NODE_MEETS_MINIMUM=0
TAURI_NPM_MEETS_MINIMUM=0
TAURI_NODE_SCOPE_OK=0
TAURI_NPM_SCOPE_OK=0
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
TAURI_INVOKING_USER="${DEBIAN_CLI_TAURI_INVOKING_USER:-}"
REFRESH="${REFRESH:-0}"
TAURI_RUNTIME_INCLUDES_XDG_UTILS=0
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

resolve.invoking.user() {
  if [[ -n "${TAURI_INVOKING_USER}" ]]; then
    return 0
  fi

  if [[ -n "${SUDO_USER:-}" ]]; then
    TAURI_INVOKING_USER="${SUDO_USER}"
    return 0
  fi

  TAURI_INVOKING_USER="$(id -un 2>/dev/null || true)"
}

collect.sudo.env.args() {
  local -n _out="$1"
  local name=""

  resolve.invoking.user

  while IFS= read -r name; do
    case "${name}" in
      DEBIAN_CLI_TAURI_*|PAGES_BASE_URL|TMP_ROOT_DIR|TMP_DIR|REFRESH)
        _out+=("${name}=${!name}")
        ;;
    esac
  done < <(compgen -e)

  _out+=("DEBIAN_CLI_TAURI_INVOKING_USER=${TAURI_INVOKING_USER}")
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
  sudo_env=()

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${TAURI_SUDO_REEXEC}" = "1" ]]; then
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
  sudo_env+=("DEBIAN_CLI_TAURI_SUDO_REEXEC=1")

  if script_path="$(current.script.path)"; then
    exec sudo env "${sudo_env[@]}" bash "${script_path}" "$@"
  fi

  if command -v wget >/dev/null 2>&1; then
    exec sudo env "${sudo_env[@]}" bash -c \
      'wget -qO- "$1" | bash -s -- "${@:2}"' \
      bash "${TAURI_SELF_URL}" "$@"
  fi

  if command -v curl >/dev/null 2>&1; then
    exec sudo env "${sudo_env[@]}" bash -c \
      'curl -fsSL "$1" | bash -s -- "${@:2}"' \
      bash "${TAURI_SELF_URL}" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because neither wget nor curl is available."
  exit 1
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

version.major() {
  local raw="${1:-}"
  raw="${raw#v}"
  raw="${raw%%.*}"
  case "${raw}" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "${raw}" ;;
  esac
}

major.ge() {
  local current_major min_major
  current_major="$(version.major "${1:-}")"
  min_major="$(version.major "${2:-0}")"
  [[ "${current_major}" -ge "${min_major}" ]]
}

resolved.path() {
  local path="${1:-}"

  if [[ -z "${path}" ]]; then
    printf 'missing'
    return 0
  fi

  readlink -f "${path}" 2>/dev/null || printf '%s' "${path}"
}

path.supports.scope() {
  local scope="${1:-private}"
  local resolved="${2:-missing}"

  if [[ -z "${resolved}" || "${resolved}" == "missing" ]]; then
    return 1
  fi

  case "${scope}" in
    shared)
      [[ "${resolved}" != /root/* ]]
      ;;
    *)
      return 0
      ;;
  esac
}

detect.node.npm() {
  TAURI_NODE_CURRENT_PATH="$(command -v node 2>/dev/null || true)"
  TAURI_NPM_CURRENT_PATH="$(command -v npm 2>/dev/null || true)"
  TAURI_NODE_CURRENT_VERSION="$(node --version 2>/dev/null || true)"
  TAURI_NPM_CURRENT_VERSION="$(npm --version 2>/dev/null || true)"
  [[ -n "${TAURI_NODE_CURRENT_PATH}" ]] || TAURI_NODE_CURRENT_PATH="missing"
  [[ -n "${TAURI_NPM_CURRENT_PATH}" ]] || TAURI_NPM_CURRENT_PATH="missing"
  TAURI_NODE_CURRENT_REALPATH="$(resolved.path "${TAURI_NODE_CURRENT_PATH}")"
  TAURI_NPM_CURRENT_REALPATH="$(resolved.path "${TAURI_NPM_CURRENT_PATH}")"
  [[ -n "${TAURI_NODE_CURRENT_VERSION}" ]] || TAURI_NODE_CURRENT_VERSION="missing"
  [[ -n "${TAURI_NPM_CURRENT_VERSION}" ]] || TAURI_NPM_CURRENT_VERSION="missing"

  if [[ "${TAURI_NODE_CURRENT_VERSION}" != "missing" ]] && major.ge "${TAURI_NODE_CURRENT_VERSION}" "${TAURI_NODE_MIN_MAJOR}"; then
    TAURI_NODE_MEETS_MINIMUM=1
  else
    TAURI_NODE_MEETS_MINIMUM=0
  fi

  if [[ "${TAURI_NPM_CURRENT_VERSION}" != "missing" ]] && major.ge "${TAURI_NPM_CURRENT_VERSION}" "${TAURI_NPM_MIN_MAJOR}"; then
    TAURI_NPM_MEETS_MINIMUM=1
  else
    TAURI_NPM_MEETS_MINIMUM=0
  fi

  if path.supports.scope "${TAURI_NODE_INSTALL_SCOPE}" "${TAURI_NODE_CURRENT_REALPATH}"; then
    TAURI_NODE_SCOPE_OK=1
  else
    TAURI_NODE_SCOPE_OK=0
  fi

  if path.supports.scope "${TAURI_NODE_INSTALL_SCOPE}" "${TAURI_NPM_CURRENT_REALPATH}"; then
    TAURI_NPM_SCOPE_OK=1
  else
    TAURI_NPM_SCOPE_OK=0
  fi
}

resolve.node.install.effective() {
  detect.node.npm

  TAURI_INSTALL_NODE_REQUESTED="${TAURI_INSTALL_NODE:-0}"
  TAURI_INSTALL_NODE_EFFECTIVE="${TAURI_INSTALL_NODE_REQUESTED}"

  if is.true "${TAURI_INSTALL_NODE_REQUESTED}"; then
    if [[ "${TAURI_NODE_MEETS_MINIMUM}" -eq 1 && "${TAURI_NPM_MEETS_MINIMUM}" -eq 1 && "${TAURI_NODE_SCOPE_OK}" -eq 1 && "${TAURI_NPM_SCOPE_OK}" -eq 1 ]]; then
      TAURI_INSTALL_NODE_EFFECTIVE=0
    else
      TAURI_INSTALL_NODE_EFFECTIVE=1
    fi
  fi

  TAURI_INSTALL_NODE="${TAURI_INSTALL_NODE_EFFECTIVE}"
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

require.valid.node.install.scope() {
  case "${TAURI_NODE_INSTALL_SCOPE}" in
    private|shared) ;;
    *)
      log.error "Unsupported Node install scope: ${TAURI_NODE_INSTALL_SCOPE}"
      log.error "Use one of: private, shared"
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
  if is.true "${TAURI_INSTALL_NODE_EFFECTIVE}" && [[ "${FEATURE_MODE}" != "preflight" ]] && [[ ! -r "${repo_root}/ansible/${NODE_PLAYBOOK_REL}" ]]; then
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

  if is.true "${TAURI_INSTALL_NODE_EFFECTIVE}" && [[ "${FEATURE_MODE}" != "preflight" ]]; then
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

confirm.tauri.runtime.packages() {
  if [[ ! -f "${TAURI_PLAYBOOK_PATH}" ]]; then
    log.error "Tauri playbook missing: ${TAURI_PLAYBOOK_PATH}"
    exit 1
  fi

  if grep -Eq '^[[:space:]]*-[[:space:]]*xdg-utils([[:space:]]|$)' "${TAURI_PLAYBOOK_PATH}"; then
    TAURI_RUNTIME_INCLUDES_XDG_UTILS=1
  else
    TAURI_RUNTIME_INCLUDES_XDG_UTILS=0
  fi

  log "Tauri runtime includes mandatory xdg-utils: ${TAURI_RUNTIME_INCLUDES_XDG_UTILS}"

  if ! is.true "${TAURI_RUNTIME_INCLUDES_XDG_UTILS}"; then
    log.error "Fetched Tauri playbook must include xdg-utils in tauri_runtime_packages."
    exit 1
  fi
tauri_install_rust: $(bool.yaml "${TAURI_INSTALL_RUST}")
tauri_rust_toolchain: $(yaml.quote "${TAURI_RUST_TOOLCHAIN}")
tauri_rust_user: $(yaml.quote "${TAURI_RUST_USER}")
tauri_invoking_user: $(yaml.quote "${TAURI_INVOKING_USER}")
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
node_install_scope: $(yaml.quote "${TAURI_NODE_INSTALL_SCOPE}")
node_shared_nvm_dir: $(yaml.quote "${TAURI_NODE_SHARED_NVM_DIR}")
node_nvm_dir: $(yaml.quote "${TAURI_NODE_NVM_DIR}")
node_version: $(yaml.quote "${TAURI_NODE_VERSION}")
node_min_major: $(yaml.quote "${TAURI_NODE_MIN_MAJOR}")
node_npm_min_major: $(yaml.quote "${TAURI_NPM_MIN_MAJOR}")
node_install_policy: "if_missing_or_too_old"
node_enable_corepack: $(bool.yaml "${TAURI_ENABLE_COREPACK}")
node_create_system_symlinks: true
EOF_VARS
  log "Prepared CLI/Tauri extra-vars: ${TAURI_EXTRA_VARS_PATH}"
}

run.tauri.feature() {
  write.tauri.extra.vars.file
  if is.true "${TAURI_INSTALL_NODE_EFFECTIVE}" && [[ "${FEATURE_MODE}" != "preflight" ]]; then
    log "Running Debian Node feature for Tauri toolchain..."
    run.feature.playbook "${NODE_PLAYBOOK_PATH}" -e "@${TAURI_EXTRA_VARS_PATH}"
  fi
  log "Running Debian Tauri feature..."
  run.feature.playbook "${TAURI_PLAYBOOK_PATH}" -e "@${TAURI_EXTRA_VARS_PATH}"
}

main() {
  resolve.invoking.user
  ensure.root.or.sudo.reexec "$@"
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host
  require.valid.mode
  require.valid.profile
  resolve.profile.defaults
  require.valid.node.install.scope
  resolve.node.install.effective
  require.valid.cli.method

  log "Feature mode: ${FEATURE_MODE}"
  log "Tauri profile: ${TAURI_PROFILE}"
  log "Install runtime libs: ${TAURI_INSTALL_RUNTIME}"
  log "Install build deps: ${TAURI_INSTALL_BUILD_DEPS}"
  log "Install Node playbook requested: ${TAURI_INSTALL_NODE_REQUESTED:-0}"
  log "Node install scope: ${TAURI_NODE_INSTALL_SCOPE}"
  log "Node runtime path: ${TAURI_NODE_CURRENT_PATH} -> ${TAURI_NODE_CURRENT_REALPATH} (scope_ok=${TAURI_NODE_SCOPE_OK})"
  log "npm runtime path: ${TAURI_NPM_CURRENT_PATH} -> ${TAURI_NPM_CURRENT_REALPATH} (scope_ok=${TAURI_NPM_SCOPE_OK})"
  log "Existing Node: ${TAURI_NODE_CURRENT_VERSION} (min major ${TAURI_NODE_MIN_MAJOR}; ok=${TAURI_NODE_MEETS_MINIMUM})"
  log "Existing npm: ${TAURI_NPM_CURRENT_VERSION} (min major ${TAURI_NPM_MIN_MAJOR}; ok=${TAURI_NPM_MEETS_MINIMUM})"
  log "Install Node playbook effective: ${TAURI_INSTALL_NODE_EFFECTIVE:-0}"
  log "Install Rust: ${TAURI_INSTALL_RUST}"
  log "Install Tauri CLI: ${TAURI_INSTALL_CLI}"

  ensure.local.ansible
  prepare.feature.files
  confirm.tauri.runtime.packages
