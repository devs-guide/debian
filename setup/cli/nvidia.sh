#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/nvidia
## Opt-in Debian NVIDIA driver and CUDA readiness runner.
##
## Local usage:
##   ./setup/cli/nvidia.sh [preflight|apply|validate|upgrade] [options]
##
## Published usage (read-only by default):
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia | bash
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia | bash -s -- preflight
##
## An installation is always explicit. For example:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia | bash -s -- apply \
##     --profile=llm --driver-source=nvidia --cuda-source=nvidia \
##     --cuda-version=<approved-exact-minor>
##
## IMPORTANT: export DEBIAN_NVIDIA_* variables before a wget|bash pipeline, or
## place them on the right side of the pipe. Assignments before wget affect wget,
## not this script.

set -euo pipefail

readonly EXIT_OPERATOR_ACTION=2
readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.nvidia] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.nvidia][error] %s\n' "$*" >&2; }
log.warn() { printf '[setup.cli.nvidia][warn] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/nvidia}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
NVIDIA_SELF_URL="${DEBIAN_NVIDIA_SELF_URL:-${PAGES_BASE_URL}/setup/cli/nvidia}"
NVIDIA_SUDO_REEXEC="${DEBIAN_NVIDIA_SUDO_REEXEC:-0}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("cli/nvidia.yml")
RUNTIME_SUPPORT_REFS=("packages.yml")
NVIDIA_PLAYBOOK_REL="cli/nvidia.yml"
NVIDIA_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NVIDIA_PLAYBOOK_REL}"
NVIDIA_EXTRA_VARS_PATH="${TMP_DIR}/cli.nvidia.extra-vars.yml"
PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
REFRESH="${REFRESH:-0}"

FEATURE_MODE="${DEBIAN_NVIDIA_MODE:-preflight}"
NVIDIA_PROFILE="${DEBIAN_NVIDIA_PROFILE:-llm}"
NVIDIA_DRIVER_SOURCE="${DEBIAN_NVIDIA_DRIVER_SOURCE:-auto}"
NVIDIA_CUDA_SOURCE="${DEBIAN_NVIDIA_CUDA_SOURCE:-auto}"
NVIDIA_DRIVER_CHANNEL="${DEBIAN_NVIDIA_DRIVER_CHANNEL:-production}"
NVIDIA_DRIVER_BRANCH="${DEBIAN_NVIDIA_DRIVER_BRANCH:-}"
NVIDIA_DRIVER_VERSION="${DEBIAN_NVIDIA_DRIVER_VERSION:-}"
NVIDIA_CUDA_VERSION="${DEBIAN_NVIDIA_CUDA_VERSION:-}"
NVIDIA_KERNEL_MODULE_FLAVOR="${DEBIAN_NVIDIA_KERNEL_MODULE_FLAVOR:-auto}"
NVIDIA_GPU_SELECT="${DEBIAN_NVIDIA_GPU_SELECT:-all}"
NVIDIA_REQUIRE_GPU_COUNT="${DEBIAN_NVIDIA_REQUIRE_GPU_COUNT:-}"
NVIDIA_REQUIRE_COMPUTE_CAPABILITIES="${DEBIAN_NVIDIA_REQUIRE_COMPUTE_CAPABILITIES:-}"
NVIDIA_PERSISTENCE="${DEBIAN_NVIDIA_PERSISTENCE:-auto}"
NVIDIA_NCCL="${DEBIAN_NVIDIA_NCCL:-auto}"
NVIDIA_RUN_P2P_TEST="${DEBIAN_NVIDIA_RUN_P2P_TEST:-0}"
NVIDIA_ALLOW_NO_GPU="${DEBIAN_NVIDIA_ALLOW_NO_GPU:-0}"
NVIDIA_ALLOW_SOURCE_MIGRATION="${DEBIAN_NVIDIA_ALLOW_SOURCE_MIGRATION:-0}"
NVIDIA_ALLOW_CUDA_MINOR_COMPAT="${DEBIAN_NVIDIA_ALLOW_CUDA_MINOR_COMPAT:-0}"
NVIDIA_ALLOW_CUSTOM_REPO="${DEBIAN_NVIDIA_ALLOW_CUSTOM_REPO:-0}"
NVIDIA_SKIP_LIVE_VALIDATE="${DEBIAN_NVIDIA_SKIP_LIVE_VALIDATE:-0}"
NVIDIA_CHECK_UPSTREAM="${DEBIAN_NVIDIA_CHECK_UPSTREAM:-0}"
NVIDIA_LATEST_IN_BRANCH="${DEBIAN_NVIDIA_LATEST_IN_BRANCH:-0}"
NVIDIA_REPO_BASE_URL="${DEBIAN_NVIDIA_REPO_BASE_URL:-}"
NVIDIA_KEYRING_URL="${DEBIAN_NVIDIA_KEYRING_URL:-}"
NVIDIA_KEYRING_SHA256="${DEBIAN_NVIDIA_KEYRING_SHA256:-}"
NVIDIA_KEY_FINGERPRINT="${DEBIAN_NVIDIA_KEY_FINGERPRINT:-}"
NVIDIA_GPU_SELECTION_SOURCE="auto"
SHOW_HELP=0

CLI_SEEN_VARIABLES=""
declare -a FEATURE_GROUP_VARS_ARGS=()

usage() {
  cat <<'EOF_USAGE'
Usage: nvidia.sh [preflight|apply|validate|upgrade] [options]

Modes:
  preflight                 Read-only inventory and policy summary (the default).
  apply                     Explicitly configure/install the selected NVIDIA state.
  validate                  Verify the installed state without package/source changes.
  upgrade                   Update only the selected, already configured NVIDIA package set.

Options:
  --profile=driver|cuda|llm
  --driver-source=auto|debian|nvidia
  --cuda-source=none|auto|debian|nvidia
  --driver-channel=production|new-feature
  --driver-branch=<branch>
  --driver-version=<exact-version>
  --cuda-version=<major.minor>
  --module-flavor=auto|open|proprietary
  --gpu=all|<uuid-or-pci-list>
  --require-gpu-count=<count>
  --require-compute-capability=<comma-separated-list>
  --persistence=auto|on|off
  --nccl=auto|on|off
  --run-p2p-test
  --allow-source-migration
  --allow-no-gpu
  --allow-cuda-minor-compat
  --skip-live-validate
  --check-upstream
  --latest-in-branch
  --help

The bare --latest option is deliberately unsupported. --latest-in-branch selects
only the highest APT candidate inside the explicitly resolved, pinned branch.
EOF_USAGE
}

is.true() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|y|Y|on|ON|On) return 0 ;;
    *) return 1 ;;
  esac
}

is.boolean() {
  case "${1:-}" in
    0|1|true|TRUE|True|false|FALSE|False|yes|YES|Yes|no|NO|No|y|Y|n|N|on|ON|On|off|OFF|Off) return 0 ;;
    *) return 1 ;;
  esac
}

bool.yaml() {
  if is.true "${1:-false}"; then
    printf 'true'
  else
    printf 'false'
  fi
}

yaml.quote() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

invalid() {
  log.error "$*"
  exit "${EXIT_USAGE}"
}

set.cli.value() {
  local variable="$1"
  local environment_name="$2"
  local value="$3"
  local environment_value="${!environment_name:-}"
  local cli_value_variable="CLI_VALUE_${variable}"

  if [[ "|${CLI_SEEN_VARIABLES}|" == *"|${variable}|"* && "${!cli_value_variable}" != "${value}" ]]; then
    invalid "Conflicting values supplied for ${environment_name}."
  fi
  if [[ -n "${!environment_name+x}" && -n "${environment_value}" && "${environment_value}" != "${value}" ]]; then
    invalid "Conflicting command-line and environment values for ${environment_name}."
  fi

  CLI_SEEN_VARIABLES="${CLI_SEEN_VARIABLES}|${variable}"
  printf -v "${cli_value_variable}" '%s' "${value}"
  printf -v "${variable}" '%s' "${value}"
}

set.cli.flag() {
  set.cli.value "$1" "$2" "1"
}

parse.arguments() {
  local first=1
  local argument=""

  while (( "$#" )); do
    argument="$1"
    shift
    if [[ "${first}" -eq 1 && "${argument}" != --* ]]; then
      set.cli.value FEATURE_MODE DEBIAN_NVIDIA_MODE "${argument}"
      first=0
      continue
    fi
    first=0

    case "${argument}" in
      --help|-h) SHOW_HELP=1 ;;
      --profile=*) set.cli.value NVIDIA_PROFILE DEBIAN_NVIDIA_PROFILE "${argument#*=}" ;;
      --driver-source=*) set.cli.value NVIDIA_DRIVER_SOURCE DEBIAN_NVIDIA_DRIVER_SOURCE "${argument#*=}" ;;
      --cuda-source=*) set.cli.value NVIDIA_CUDA_SOURCE DEBIAN_NVIDIA_CUDA_SOURCE "${argument#*=}" ;;
      --driver-channel=*) set.cli.value NVIDIA_DRIVER_CHANNEL DEBIAN_NVIDIA_DRIVER_CHANNEL "${argument#*=}" ;;
      --driver-branch=*) set.cli.value NVIDIA_DRIVER_BRANCH DEBIAN_NVIDIA_DRIVER_BRANCH "${argument#*=}" ;;
      --driver-version=*) set.cli.value NVIDIA_DRIVER_VERSION DEBIAN_NVIDIA_DRIVER_VERSION "${argument#*=}" ;;
      --cuda-version=*) set.cli.value NVIDIA_CUDA_VERSION DEBIAN_NVIDIA_CUDA_VERSION "${argument#*=}" ;;
      --module-flavor=*) set.cli.value NVIDIA_KERNEL_MODULE_FLAVOR DEBIAN_NVIDIA_KERNEL_MODULE_FLAVOR "${argument#*=}" ;;
      --gpu=*) set.cli.value NVIDIA_GPU_SELECT DEBIAN_NVIDIA_GPU_SELECT "${argument#*=}" ;;
      --require-gpu-count=*) set.cli.value NVIDIA_REQUIRE_GPU_COUNT DEBIAN_NVIDIA_REQUIRE_GPU_COUNT "${argument#*=}" ;;
      --require-compute-capability=*) set.cli.value NVIDIA_REQUIRE_COMPUTE_CAPABILITIES DEBIAN_NVIDIA_REQUIRE_COMPUTE_CAPABILITIES "${argument#*=}" ;;
      --persistence=*) set.cli.value NVIDIA_PERSISTENCE DEBIAN_NVIDIA_PERSISTENCE "${argument#*=}" ;;
      --nccl=*) set.cli.value NVIDIA_NCCL DEBIAN_NVIDIA_NCCL "${argument#*=}" ;;
      --run-p2p-test) set.cli.flag NVIDIA_RUN_P2P_TEST DEBIAN_NVIDIA_RUN_P2P_TEST ;;
      --allow-source-migration) set.cli.flag NVIDIA_ALLOW_SOURCE_MIGRATION DEBIAN_NVIDIA_ALLOW_SOURCE_MIGRATION ;;
      --allow-no-gpu) set.cli.flag NVIDIA_ALLOW_NO_GPU DEBIAN_NVIDIA_ALLOW_NO_GPU ;;
      --allow-cuda-minor-compat) set.cli.flag NVIDIA_ALLOW_CUDA_MINOR_COMPAT DEBIAN_NVIDIA_ALLOW_CUDA_MINOR_COMPAT ;;
      --skip-live-validate) set.cli.flag NVIDIA_SKIP_LIVE_VALIDATE DEBIAN_NVIDIA_SKIP_LIVE_VALIDATE ;;
      --check-upstream) set.cli.flag NVIDIA_CHECK_UPSTREAM DEBIAN_NVIDIA_CHECK_UPSTREAM ;;
      --latest-in-branch) set.cli.flag NVIDIA_LATEST_IN_BRANCH DEBIAN_NVIDIA_LATEST_IN_BRANCH ;;
      --latest) invalid "--latest is ambiguous and unsupported; use --latest-in-branch instead." ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

require.enum() {
  local label="$1"
  local value="$2"
  shift 2
  local allowed=""

  for allowed in "$@"; do
    [[ "${value}" == "${allowed}" ]] && return 0
  done
  invalid "Unsupported ${label}: ${value}"
}

validate.boolean() {
  local environment_name="$1"
  local value="$2"
  is.boolean "${value}" || invalid "${environment_name} must be a boolean value."
}

resolve.defaults() {
  if [[ -n "${DEBIAN_NVIDIA_GPU_IDS:-}" ]]; then
    if [[ -n "${DEBIAN_NVIDIA_GPU_SELECT+x}" || "|${CLI_SEEN_VARIABLES}|" == *"|NVIDIA_GPU_SELECT|"* ]]; then
      invalid "DEBIAN_NVIDIA_GPU_IDS cannot be combined with DEBIAN_NVIDIA_GPU_SELECT or --gpu."
    fi
    NVIDIA_GPU_SELECT="${DEBIAN_NVIDIA_GPU_IDS}"
    NVIDIA_GPU_SELECTION_SOURCE="legacy-index"
    log.warn "DEBIAN_NVIDIA_GPU_IDS is deprecated; indices will be resolved to UUIDs for this invocation."
  fi

  if [[ -z "${NVIDIA_DRIVER_BRANCH}" && "${NVIDIA_DRIVER_CHANNEL}" == "production" ]]; then
    NVIDIA_DRIVER_BRANCH="595"
  fi
}

validate.configuration() {
  require.enum mode "${FEATURE_MODE}" preflight apply validate upgrade
  require.enum profile "${NVIDIA_PROFILE}" driver cuda llm
  require.enum driver-source "${NVIDIA_DRIVER_SOURCE}" auto debian nvidia
  require.enum cuda-source "${NVIDIA_CUDA_SOURCE}" none auto debian nvidia
  require.enum driver-channel "${NVIDIA_DRIVER_CHANNEL}" production new-feature
  require.enum module-flavor "${NVIDIA_KERNEL_MODULE_FLAVOR}" auto open proprietary
  require.enum persistence "${NVIDIA_PERSISTENCE}" auto on off
  require.enum nccl "${NVIDIA_NCCL}" auto on off

  validate.boolean DEBIAN_NVIDIA_RUN_P2P_TEST "${NVIDIA_RUN_P2P_TEST}"
  validate.boolean DEBIAN_NVIDIA_ALLOW_NO_GPU "${NVIDIA_ALLOW_NO_GPU}"
  validate.boolean DEBIAN_NVIDIA_ALLOW_SOURCE_MIGRATION "${NVIDIA_ALLOW_SOURCE_MIGRATION}"
  validate.boolean DEBIAN_NVIDIA_ALLOW_CUDA_MINOR_COMPAT "${NVIDIA_ALLOW_CUDA_MINOR_COMPAT}"
  validate.boolean DEBIAN_NVIDIA_ALLOW_CUSTOM_REPO "${NVIDIA_ALLOW_CUSTOM_REPO}"
  validate.boolean DEBIAN_NVIDIA_SKIP_LIVE_VALIDATE "${NVIDIA_SKIP_LIVE_VALIDATE}"
  validate.boolean DEBIAN_NVIDIA_CHECK_UPSTREAM "${NVIDIA_CHECK_UPSTREAM}"
  validate.boolean DEBIAN_NVIDIA_LATEST_IN_BRANCH "${NVIDIA_LATEST_IN_BRANCH}"

  if [[ -n "${NVIDIA_DRIVER_BRANCH}" && ! "${NVIDIA_DRIVER_BRANCH}" =~ ^[0-9]+$ ]]; then
    invalid "Driver branch must be a numeric branch, for example 595."
  fi
  if [[ -n "${NVIDIA_DRIVER_VERSION}" && ! "${NVIDIA_DRIVER_VERSION}" =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]]; then
    invalid "Driver version has unsupported characters: ${NVIDIA_DRIVER_VERSION}"
  fi
  if [[ -n "${NVIDIA_CUDA_VERSION}" && ! "${NVIDIA_CUDA_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    invalid "CUDA version must be an exact major.minor value, for example 12.8."
  fi
  if [[ -n "${NVIDIA_REQUIRE_GPU_COUNT}" && ! "${NVIDIA_REQUIRE_GPU_COUNT}" =~ ^[0-9]+$ ]]; then
    invalid "GPU count must be a non-negative integer."
  fi
  if [[ -n "${NVIDIA_REQUIRE_COMPUTE_CAPABILITIES}" ]]; then
    local capability=""
    local -a capabilities=()
    IFS=',' read -r -a capabilities <<< "${NVIDIA_REQUIRE_COMPUTE_CAPABILITIES}"
    for capability in "${capabilities[@]}"; do
      [[ "${capability}" =~ ^[0-9]+\.[0-9]+$ ]] || invalid "Compute capabilities must be comma-separated major.minor values."
    done
  fi
  if [[ -z "${NVIDIA_GPU_SELECT}" ]]; then
    invalid "GPU selection must be all or a comma-separated UUID/PCI list."
  fi
  if [[ "${NVIDIA_GPU_SELECT}" != all && "${NVIDIA_GPU_SELECT}" == *,* ]]; then
    [[ "${NVIDIA_GPU_SELECT}" != ,* && "${NVIDIA_GPU_SELECT}" != *, ]] || invalid "GPU selection contains an empty item."
  fi

  if [[ "${NVIDIA_DRIVER_CHANNEL}" == new-feature && -z "${NVIDIA_DRIVER_BRANCH}" ]]; then
    invalid "The new-feature channel requires an explicit --driver-branch."
  fi
  if [[ -n "${NVIDIA_DRIVER_VERSION}" ]] && is.true "${NVIDIA_LATEST_IN_BRANCH}"; then
    invalid "--driver-version and --latest-in-branch cannot be combined."
  fi
  if [[ "${NVIDIA_PROFILE}" != driver && "${NVIDIA_CUDA_SOURCE}" == none ]]; then
    invalid "CUDA source cannot be none for the ${NVIDIA_PROFILE} profile."
  fi
  if [[ "${FEATURE_MODE}" == apply && "${NVIDIA_PROFILE}" != driver && -z "${NVIDIA_CUDA_VERSION}" ]]; then
    invalid "apply with the ${NVIDIA_PROFILE} profile requires --cuda-version=<major.minor>."
  fi

  local custom_value=""
  for custom_value in "${NVIDIA_REPO_BASE_URL}" "${NVIDIA_KEYRING_URL}" "${NVIDIA_KEYRING_SHA256}" "${NVIDIA_KEY_FINGERPRINT}"; do
    if [[ -n "${custom_value}" ]] && ! is.true "${NVIDIA_ALLOW_CUSTOM_REPO}"; then
      invalid "Custom repository controls require DEBIAN_NVIDIA_ALLOW_CUSTOM_REPO=1."
    fi
  done
  if [[ -n "${NVIDIA_REPO_BASE_URL}" ]]; then
    [[ "${NVIDIA_REPO_BASE_URL}" == https://* ]] || invalid "Custom repository URLs must use HTTPS."
    [[ -n "${NVIDIA_KEYRING_URL}" && -n "${NVIDIA_KEYRING_SHA256}" && -n "${NVIDIA_KEY_FINGERPRINT}" ]] || \
      invalid "A custom repository requires keyring URL, SHA-256, and signing-key fingerprint."
    [[ "${NVIDIA_KEYRING_URL}" == https://* ]] || invalid "Custom keyring URL must use HTTPS."
    [[ "${NVIDIA_KEYRING_SHA256}" =~ ^[A-Fa-f0-9]{64}$ ]] || invalid "Custom keyring SHA-256 must be 64 hexadecimal characters."
  fi
}

reset.feature.tmp.cache() {
  if is.true "${REFRESH}"; then
    log "REFRESH=1; clearing feature temporary cache under ${TMP_DIR}"
    rm -rf "${TMP_DIR}"
  fi
}

current.script.path() {
  local source_path="${BASH_SOURCE[0]:-}"
  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*) return 1 ;;
  esac
  if [[ -r "${source_path}" ]]; then
    readlink -f "${source_path}" 2>/dev/null || printf '%s\n' "${source_path}"
    return 0
  fi
  return 1
}

collect.sudo.env.args() {
  local -n output="$1"
  local name=""
  output=()
  while IFS= read -r name; do
    case "${name}" in
      DEBIAN_NVIDIA_*|PAGES_BASE_URL|TMP_ROOT_DIR|TMP_DIR|REFRESH)
        output+=("${name}=${!name}")
        ;;
    esac
  done < <(compgen -e)
}

ensure.root.or.sudo.reexec() {
  local script_path=""
  local -a sudo_env=()

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  if [[ "${NVIDIA_SUDO_REEXEC}" == 1 ]]; then
    log.error "sudo re-entry was requested but the script is still not root."
    exit 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log.error "This mode requires root privileges. Install sudo or run as root."
    exit 1
  fi

  log "Root privileges required; requesting sudo..."
  sudo -v || { log.error "sudo authentication failed or was cancelled."; exit 1; }
  collect.sudo.env.args sudo_env
  sudo_env+=("DEBIAN_NVIDIA_SUDO_REEXEC=1")

  if script_path="$(current.script.path)"; then
    exec sudo env "${sudo_env[@]}" bash "${script_path}" "$@"
  fi
  if command -v wget >/dev/null 2>&1; then
    exec sudo env "${sudo_env[@]}" bash -c \
      'wget -qO- "$1" | bash -s -- "${@:2}"' \
      bash "${NVIDIA_SELF_URL}" "$@"
  fi
  if command -v curl >/dev/null 2>&1; then
    exec sudo env "${sudo_env[@]}" bash -c \
      'curl -fsSL "$1" | bash -s -- "${@:2}"' \
      bash "${NVIDIA_SELF_URL}" "$@"
  fi
  log.error "Cannot re-enter from stdin because neither wget nor curl is available."
  exit 1
}

source.release.common() {
  local script_dir=""
  local source_path="${BASH_SOURCE[0]:-}"

  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*) ;;
    *)
      script_dir="$(cd "$(dirname "${source_path}")" && pwd)"
      if [[ -r "${script_dir}/${LOCAL_COMMON_HELPER}" ]]; then
        # shellcheck source=setup/release.common.sh
        source "${script_dir}/${LOCAL_COMMON_HELPER}"
        return
      fi
      ;;
  esac

  if ! command -v wget >/dev/null 2>&1; then
    log.error "Cannot fetch the shared helper because wget is unavailable."
    exit "${EXIT_BLOCKED}"
  fi

  mkdir -p "${TMP_DIR}"
  log "Fetching shared helper: ${COMMON_HELPER_URL}"
  wget -qO "${COMMON_HELPER_PATH}" "${COMMON_HELPER_URL}" || {
    log.error "Failed to fetch shared helper: ${COMMON_HELPER_URL}"
    exit 1
  }
  # shellcheck source=/tmp/ansible/debian/nvidia/release.common.sh
  source "${COMMON_HELPER_PATH}"
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
  local script_dir=""
  local repo_root=""
  local file=""
  local source_path="${BASH_SOURCE[0]:-}"

  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*) return 1 ;;
  esac
  script_dir="$(cd "$(dirname "${source_path}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"

  for file in "${GROUP_VARS_FILES[@]}"; do
    [[ -r "${repo_root}/ansible/group_vars/${file}" ]] || return 1
  done
  for file in "${RUNTIME_SUPPORT_REFS[@]}"; do
    [[ -s "${repo_root}/ansible/${file}" ]] || return 1
  done
  [[ -r "${repo_root}/ansible/${NVIDIA_PLAYBOOK_REL}" ]] || return 1

  PLAYBOOK_ROOT="${repo_root}/ansible"
  PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
  NVIDIA_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${NVIDIA_PLAYBOOK_REL}"
  reset.feature.extra.vars.args
  log "Using local feature files from ${repo_root}"
}

fetch.feature.file() {
  local url="$1"
  local destination="$2"
  mkdir -p "$(dirname "${destination}")"
  log "Fetching feature file: ${url}"
  wget -qO "${destination}" "${url}" || {
    log.error "Failed to fetch feature file: ${url}"
    exit 1
  }
  [[ -s "${destination}" ]] || { log.error "Feature file is empty: ${url}"; exit 1; }
}

fetch.runtime.support.file() {
  local reference="$1"
  local source_url="${PAGES_BASE_URL}/ansible/${reference}"
  local destination="${PLAYBOOK_ROOT}/${reference}"

  mkdir -p "$(dirname "${destination}")"
  log "Fetching runtime support file: ${source_url}"
  wget -qO "${destination}" "${source_url}" || {
    log.error "Failed to fetch runtime support file: ${source_url}"
    exit "${EXIT_BLOCKED}"
  }
  [[ -s "${destination}" ]] || {
    log.error "Required runtime support file is missing or empty: ${destination}"
    exit "${EXIT_BLOCKED}"
  }
}

validate.runtime.support.files() {
  local reference=""
  local path=""
  for reference in "${RUNTIME_SUPPORT_REFS[@]}"; do
    path="${PLAYBOOK_ROOT}/${reference}"
    if [[ ! -s "${path}" ]]; then
      log.error "Required runtime support file is missing or empty: ${path}"
      exit "${EXIT_BLOCKED}"
    fi
  done
}

prepare.feature.files() {
  local file=""
  if use.local.feature.files; then
    validate.runtime.support.files
    return
  fi

  mkdir -p "${PLAYBOOK_GROUP_VARS_DIR}"
  for file in "${GROUP_VARS_FILES[@]}"; do
    fetch.feature.file "${PAGES_BASE_URL}/ansible/group_vars/${file}" "${PLAYBOOK_GROUP_VARS_DIR}/${file}"
  done
  for file in "${RUNTIME_SUPPORT_REFS[@]}"; do
    fetch.runtime.support.file "${file}"
  done
  fetch.feature.file "${PAGES_BASE_URL}/ansible/${NVIDIA_PLAYBOOK_REL}" "${NVIDIA_PLAYBOOK_PATH}"
  reset.feature.extra.vars.args
  validate.runtime.support.files
}

write.nvidia.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${NVIDIA_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
nvidia_mode: $(yaml.quote "${FEATURE_MODE}")
nvidia_profile: $(yaml.quote "${NVIDIA_PROFILE}")
nvidia_driver_source: $(yaml.quote "${NVIDIA_DRIVER_SOURCE}")
nvidia_cuda_source: $(yaml.quote "${NVIDIA_CUDA_SOURCE}")
nvidia_driver_channel: $(yaml.quote "${NVIDIA_DRIVER_CHANNEL}")
nvidia_driver_branch: $(yaml.quote "${NVIDIA_DRIVER_BRANCH}")
nvidia_driver_version: $(yaml.quote "${NVIDIA_DRIVER_VERSION}")
nvidia_cuda_version: $(yaml.quote "${NVIDIA_CUDA_VERSION}")
nvidia_kernel_module_flavor: $(yaml.quote "${NVIDIA_KERNEL_MODULE_FLAVOR}")
nvidia_gpu_select: $(yaml.quote "${NVIDIA_GPU_SELECT}")
nvidia_gpu_selection_source: $(yaml.quote "${NVIDIA_GPU_SELECTION_SOURCE}")
nvidia_require_gpu_count: $(yaml.quote "${NVIDIA_REQUIRE_GPU_COUNT}")
nvidia_require_compute_capabilities: $(yaml.quote "${NVIDIA_REQUIRE_COMPUTE_CAPABILITIES}")
nvidia_persistence: $(yaml.quote "${NVIDIA_PERSISTENCE}")
nvidia_nccl: $(yaml.quote "${NVIDIA_NCCL}")
nvidia_run_p2p_test: $(bool.yaml "${NVIDIA_RUN_P2P_TEST}")
nvidia_allow_no_gpu: $(bool.yaml "${NVIDIA_ALLOW_NO_GPU}")
nvidia_allow_source_migration: $(bool.yaml "${NVIDIA_ALLOW_SOURCE_MIGRATION}")
nvidia_allow_cuda_minor_compat: $(bool.yaml "${NVIDIA_ALLOW_CUDA_MINOR_COMPAT}")
nvidia_allow_custom_repo: $(bool.yaml "${NVIDIA_ALLOW_CUSTOM_REPO}")
nvidia_skip_live_validate: $(bool.yaml "${NVIDIA_SKIP_LIVE_VALIDATE}")
nvidia_check_upstream: $(bool.yaml "${NVIDIA_CHECK_UPSTREAM}")
nvidia_latest_in_branch: $(bool.yaml "${NVIDIA_LATEST_IN_BRANCH}")
nvidia_repo_base_url: $(yaml.quote "${NVIDIA_REPO_BASE_URL}")
nvidia_keyring_url: $(yaml.quote "${NVIDIA_KEYRING_URL}")
nvidia_keyring_sha256: $(yaml.quote "${NVIDIA_KEYRING_SHA256}")
nvidia_key_fingerprint: $(yaml.quote "${NVIDIA_KEY_FINGERPRINT}")
EOF_VARS
  log "Prepared NVIDIA extra-vars: ${NVIDIA_EXTRA_VARS_PATH}"
}

run.feature.playbook() {
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" -e "@${NVIDIA_EXTRA_VARS_PATH}" "${NVIDIA_PLAYBOOK_PATH}"
}

report.command() {
  local label="$1"
  shift
  {
    printf '\n## %s\n' "${label}"
    "$@" 2>&1 || true
  } | tee -a "${PREFLIGHT_REPORT_PATH}"
}

report.text() {
  local label="$1"
  local path="$2"
  {
    printf '\n## %s\n' "${label}"
    if [[ -r "${path}" ]]; then
      sed -n '1,240p' "${path}"
    else
      printf 'unavailable: %s\n' "${path}"
    fi
  } | tee -a "${PREFLIGHT_REPORT_PATH}"
}

run.read.only.preflight() {
  local running_headers="linux-headers-$(uname -r)"
  local architecture="unavailable"
  mkdir -p "${TMP_DIR}"
  : > "${PREFLIGHT_REPORT_PATH}"

  if command -v dpkg >/dev/null 2>&1; then
    architecture="$(dpkg --print-architecture 2>/dev/null || printf 'unavailable')"
  fi

  log "Read-only NVIDIA preflight report: ${PREFLIGHT_REPORT_PATH}"
  report.text "os-release" /etc/os-release
  report.command "kernel and architecture" uname -a
  report.command "dpkg architecture" dpkg --print-architecture
  report.command "running-kernel header candidate (${running_headers})" apt-cache policy "${running_headers}"
  report.command "NVIDIA PCI inventory" lspci -Dnnk
  report.command "loaded NVIDIA/nouveau modules" sh -c 'lsmod | grep -E "^(nvidia|nouveau)" || true'
  report.command "installed NVIDIA and CUDA packages" sh -c "dpkg-query -W -f='\${binary:Package} \${Version}\\n' '*nvidia*' '*cuda*' 2>/dev/null || true"
  report.command "held APT packages" sh -c 'apt-mark showhold || true'
  report.command "Secure Boot state" mokutil --sb-state
  report.command "DKMS status" dkms status
  report.command "NVIDIA module metadata" modinfo nvidia
  report.command "NVIDIA live inventory" nvidia-smi
  report.command "NVIDIA GPU list" nvidia-smi -L
  report.command "NVIDIA GPU query" nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap --format=csv,noheader
  report.command "NVIDIA topology" nvidia-smi topo -m
  report.command "NVIDIA NVLink status" nvidia-smi nvlink -s

  log "Requested policy: mode=${FEATURE_MODE} profile=${NVIDIA_PROFILE} driver_source=${NVIDIA_DRIVER_SOURCE} cuda_source=${NVIDIA_CUDA_SOURCE} driver_branch=${NVIDIA_DRIVER_BRANCH} cuda_version=${NVIDIA_CUDA_VERSION:-unset}"
  if [[ "${architecture}" != amd64 ]]; then
    log.warn "Initial NVIDIA apply support is restricted to Debian amd64; this host reports ${architecture}."
  fi
  log "Preflight is read-only: it did not run apt update, install packages, load modules, alter APT sources, or write persistent NVIDIA facts."
  if [[ "${NVIDIA_PROFILE}" != driver && -z "${NVIDIA_CUDA_VERSION}" ]]; then
    log "To apply this profile, choose an approved exact CUDA minor: --cuda-version=<major.minor>."
  fi
}

require.supported.platform() {
  local architecture=""
  architecture="$(dpkg --print-architecture)"
  if [[ "${architecture}" != amd64 ]]; then
    log.error "NVIDIA apply support is currently restricted to Debian amd64; detected ${architecture}."
    exit "${EXIT_BLOCKED}"
  fi
}

run.managed.mode() {
  ensure.root.or.sudo.reexec "$@"
  source.release.common
  require.root
  require.apt
  require.debian
  require.supported.platform
  reset.feature.tmp.cache
  prepare.feature.files

  if [[ "${FEATURE_MODE}" == validate ]]; then
    if [[ ! -x "${ANSIBLE_VENV_BIN}" ]]; then
      log.error "validate will not bootstrap or modify the Ansible controller; managed Ansible is missing at ${ANSIBLE_VENV_BIN}."
      exit "${EXIT_BLOCKED}"
    fi
  else
    ensure.local.ansible
  fi

  write.nvidia.extra.vars.file
  log "Running NVIDIA playbook in ${FEATURE_MODE} mode."
  run.feature.playbook
}

main() {
  parse.arguments "$@"
  if [[ "${SHOW_HELP}" -eq 1 ]]; then
    usage
    return 0
  fi
  resolve.defaults
  validate.configuration

  if [[ "${FEATURE_MODE}" == preflight ]]; then
    reset.feature.tmp.cache
    prepare.feature.files
    run.read.only.preflight
    return 0
  fi
  run.managed.mode "$@"
}

main "$@"
