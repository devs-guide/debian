#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/llm/host.sh
# Shared LLM host-readiness runner. It inventories CPU, NUMA, memory, and
# producer-owned GPU facts before any runtime- or model-specific feature runs.
#
# wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
#   bash -s -- preflight --profile=generic

set -euo pipefail

readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.llm.host] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.llm.host][error] %s\n' "$*" >&2; }

RUNNER_TMP_PARENT="${DEBIAN_RUNNER_TMP_PARENT:-/tmp}"
TMP_DIR=""
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT=""
HOST_PLAYBOOK_PATH=""
PACKAGE_PLAYBOOK_PATH=""
HOST_EXTRA_VARS_PATH=""
PREFLIGHT_REPORT_PATH=""
LOCAL_RUNNER_HELPER="../../runner.common.sh"
RUNNER_HELPER_NAME="runner.common.sh"
RUNNER_HELPER_URL="${PAGES_BASE_URL}/setup/${RUNNER_HELPER_NAME}"
RUNNER_HELPER_PATH=""
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("install.packages.yml" "cli/llm/host.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "files/llm/host-inventory.py"
)
FEATURE_TEMPLATE_REFS=()

FEATURE_MODE="${DEBIAN_LLM_HOST_MODE:-preflight}"
LLM_HOST_PROFILE="${DEBIAN_LLM_HOST_PROFILE:-generic}"
LLM_HOST_OWNER="${DEBIAN_LLM_HOST_OWNER:-}"
LLM_HOST_GROUP="${DEBIAN_LLM_HOST_GROUP:-}"
LLM_HOST_RESERVE_GIB="${DEBIAN_LLM_HOST_RESERVE_GIB:-96}"
LLM_HOST_ALLOW_LOW_RESERVE="${DEBIAN_LLM_HOST_ALLOW_LOW_RESERVE:-false}"
LLM_HOST_GPU_RESERVE_MIB="${DEBIAN_LLM_HOST_GPU_RESERVE_MIB:-4096}"
LLM_HOST_REQUIRE_PHYSICAL_CORES="${DEBIAN_LLM_HOST_REQUIRE_PHYSICAL_CORES:-0}"
LLM_HOST_REQUIRE_MEMORY_MODE="${DEBIAN_LLM_HOST_REQUIRE_MEMORY_MODE:-false}"
LLM_HOST_REQUIRE_NVIDIA="${DEBIAN_LLM_HOST_REQUIRE_NVIDIA:-false}"
LLM_HOST_REQUIRE_NVLINK="${DEBIAN_LLM_HOST_REQUIRE_NVLINK:-false}"
LLM_HOST_REQUIRE_P2P="${DEBIAN_LLM_HOST_REQUIRE_P2P:-false}"
LLM_HOST_INSTALL_SUPPORT_PACKAGES="${DEBIAN_LLM_HOST_INSTALL_SUPPORT_PACKAGES:-false}"
SHOW_HELP=0
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

usage() {
  cat <<'EOF_USAGE'
Usage: host.sh [preflight|apply|validate] [options]

Modes:
  preflight                 Read-only host and producer-fact report (default).
  apply                     Validate and persist the LLM host contract.
  validate                  Revalidate and refresh the same contract.

Options:
  --profile=generic|icelake-pmem-dual-3090
  --owner=USER
  --group=GROUP
  --host-reserve-gib=N
  --allow-low-host-reserve
  --gpu-reserve-mib=N
  --require-physical-cores=N
  --require-memory-mode
  --require-nvidia
  --require-nvlink
  --require-p2p
  --install-support-packages
  --no-install-support-packages
  --help

The host runner never downloads a model or installs an LLM runtime. It does
not alter swap, sysctl, CPU-governor, kernel, bootloader, or NVIDIA policy.
EOF_USAGE
}

invalid() { log.error "$*"; exit "${EXIT_USAGE}"; }

parse.arguments() {
  local first=1 argument=""
  while (($#)); do
    argument="$1"
    shift
    if [[ "${first}" -eq 1 && "${argument}" != --* ]]; then
      FEATURE_MODE="${argument}"
      first=0
      continue
    fi
    first=0
    case "${argument}" in
      --help|-h) SHOW_HELP=1 ;;
      --profile=*) LLM_HOST_PROFILE="${argument#*=}" ;;
      --owner=*) LLM_HOST_OWNER="${argument#*=}" ;;
      --group=*) LLM_HOST_GROUP="${argument#*=}" ;;
      --host-reserve-gib=*) LLM_HOST_RESERVE_GIB="${argument#*=}" ;;
      --allow-low-host-reserve) LLM_HOST_ALLOW_LOW_RESERVE=true ;;
      --gpu-reserve-mib=*) LLM_HOST_GPU_RESERVE_MIB="${argument#*=}" ;;
      --require-physical-cores=*) LLM_HOST_REQUIRE_PHYSICAL_CORES="${argument#*=}" ;;
      --require-memory-mode) LLM_HOST_REQUIRE_MEMORY_MODE=true ;;
      --require-nvidia) LLM_HOST_REQUIRE_NVIDIA=true ;;
      --require-nvlink) LLM_HOST_REQUIRE_NVLINK=true ;;
      --require-p2p) LLM_HOST_REQUIRE_P2P=true ;;
      --install-support-packages) LLM_HOST_INSTALL_SUPPORT_PACKAGES=true ;;
      --no-install-support-packages) LLM_HOST_INSTALL_SUPPORT_PACKAGES=false ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

resolve.owner.and.group() {
  if [[ -z "${LLM_HOST_OWNER}" ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
      LLM_HOST_OWNER="${SUDO_USER}"
    else
      LLM_HOST_OWNER="$(id -un)"
    fi
  fi
  [[ "${LLM_HOST_OWNER}" != root ]] || invalid "A non-root --owner is required for managed LLM paths."
  [[ "${LLM_HOST_OWNER}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || invalid "Invalid owner name: ${LLM_HOST_OWNER}"

  if [[ -z "${LLM_HOST_GROUP}" ]]; then
    LLM_HOST_GROUP="$(id -gn "${LLM_HOST_OWNER}" 2>/dev/null || true)"
  fi
  [[ "${LLM_HOST_GROUP}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || invalid "Invalid or unresolved group name: ${LLM_HOST_GROUP:-unset}"
}

validate.configuration() {
  case "${FEATURE_MODE}" in preflight|apply|validate) ;; *) invalid "Unsupported mode: ${FEATURE_MODE}" ;; esac
  case "${LLM_HOST_PROFILE}" in generic|icelake-pmem-dual-3090) ;; *) invalid "Unsupported profile: ${LLM_HOST_PROFILE}" ;; esac
  for value in \
    "${LLM_HOST_RESERVE_GIB}" \
    "${LLM_HOST_GPU_RESERVE_MIB}" \
    "${LLM_HOST_REQUIRE_PHYSICAL_CORES}"; do
    [[ "${value}" =~ ^[0-9]+$ ]] || invalid "Reserve and physical-core values must be non-negative integers."
  done
  ((10#${LLM_HOST_RESERVE_GIB} >= 1)) || invalid "--host-reserve-gib must be at least 1."
  case "${LLM_HOST_ALLOW_LOW_RESERVE}" in true|false) ;; *) invalid "Invalid low-reserve policy." ;; esac
  case "${LLM_HOST_INSTALL_SUPPORT_PACKAGES}" in true|false) ;; *) invalid "Invalid package-install policy." ;; esac
  if [[ "${LLM_HOST_REQUIRE_P2P}" == true && "${LLM_HOST_REQUIRE_NVLINK}" != true ]]; then
    invalid "--require-p2p also requires --require-nvlink."
  fi
  if [[ "${LLM_HOST_REQUIRE_NVLINK}" == true && "${LLM_HOST_REQUIRE_NVIDIA}" != true ]]; then
    invalid "--require-nvlink also requires --require-nvidia."
  fi
  if [[ "${LLM_HOST_PROFILE}" == icelake-pmem-dual-3090 ]]; then
    LLM_HOST_REQUIRE_MEMORY_MODE=true
    LLM_HOST_REQUIRE_NVIDIA=true
    LLM_HOST_REQUIRE_NVLINK=true
    LLM_HOST_REQUIRE_P2P=true
    if [[ "${LLM_HOST_REQUIRE_PHYSICAL_CORES}" == 0 ]]; then
      LLM_HOST_REQUIRE_PHYSICAL_CORES=36
    fi
  fi
  resolve.owner.and.group
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  HOST_EXTRA_VARS_PATH="${TMP_DIR}/cli.llm.host.extra-vars.yml"
  PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
  COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
}

source.runner.common() {
  local source_path="${BASH_SOURCE[0]:-}" script_dir="" local_helper="" bootstrap_dir="" repo_root=""
  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*) ;;
    *)
      script_dir="$(cd "$(dirname "${source_path}")" && pwd)"
      local_helper="${script_dir}/${LOCAL_RUNNER_HELPER}"
      if [[ -r "${local_helper}" ]]; then
        repo_root="$(cd "${script_dir}/../../.." && pwd -P)"
        RUNNER_LOCAL_REPO_ROOT="${repo_root}"
        RUNNER_HELPER_PATH="$(cd "$(dirname "${local_helper}")" && pwd)/$(basename "${local_helper}")"
        # shellcheck source=setup/runner.common.sh
        source "${RUNNER_HELPER_PATH}"
        runner.create.runtime llm-host "${RUNNER_TMP_PARENT}"
        configure.runtime.paths
        return
      fi
      ;;
  esac
  command -v wget >/dev/null 2>&1 || {
    log.error "Cannot fetch the runner helper because wget is unavailable."
    exit "${EXIT_BLOCKED}"
  }
  [[ "${RUNNER_TMP_PARENT}" == /* && "${RUNNER_TMP_PARENT}" != / && -d "${RUNNER_TMP_PARENT}" && -w "${RUNNER_TMP_PARENT}" ]] || {
    log.error "Runner temporary parent must be an existing writable absolute directory other than /: ${RUNNER_TMP_PARENT}"
    exit "${EXIT_BLOCKED}"
  }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-llm-host.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  log "Fetching shared runner helper: ${RUNNER_HELPER_URL}"
  if ! wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" || [[ ! -s "${RUNNER_HELPER_PATH}" ]]; then
    log.error "Failed to fetch shared runner helper: ${RUNNER_HELPER_URL}"
    rm -f -- "${RUNNER_HELPER_PATH}"
    rmdir -- "${bootstrap_dir}" 2>/dev/null || true
    exit "${EXIT_BLOCKED}"
  fi
  bash -n "${RUNNER_HELPER_PATH}" || {
    log.error "Downloaded runner helper failed shell syntax validation."
    exit "${EXIT_BLOCKED}"
  }
  # shellcheck source=/tmp/devs-guide-llm-host.XXXXXX/runner.common.sh
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime llm-host "${bootstrap_dir}"
  configure.runtime.paths
}

source.release.common() {
  local local_setup_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_setup_root="${RUNNER_LOCAL_REPO_ROOT}/setup"
  runner.source.release.common \
    "${local_setup_root}" \
    "${PAGES_BASE_URL}/setup" \
    "${TMP_DIR}" \
    "${COMMON_HELPER_NAME}" || {
    log.error "Unable to stage the shared release helper."
    exit "${EXIT_BLOCKED}"
  }
}

prepare.feature.files() {
  local local_ansible_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_ansible_root="${RUNNER_LOCAL_REPO_ROOT}/ansible"
  runner.prepare.ansible.feature \
    "${local_ansible_root}" \
    "${PAGES_BASE_URL}/ansible" \
    "${PLAYBOOK_ROOT}" || {
    log.error "Unable to stage the LLM host Ansible manifest."
    exit "${EXIT_BLOCKED}"
  }
  PACKAGE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[0]}"
  HOST_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

write.extra.vars.file() {
  cat > "${HOST_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_catalog_url: "${PAGES_BASE_URL}/ansible/packages.yml"
package_catalog_filename: "packages.yml"
package_group_allowlist: ["llm_host_support"]
package_group_overrides:
  llm_host_support: true
llm_host_mode: "${FEATURE_MODE}"
llm_host_profile: "${LLM_HOST_PROFILE}"
llm_host_owner: "${LLM_HOST_OWNER}"
llm_host_group: "${LLM_HOST_GROUP}"
llm_host_reserve_gib: ${LLM_HOST_RESERVE_GIB}
llm_host_allow_low_reserve: ${LLM_HOST_ALLOW_LOW_RESERVE}
llm_host_gpu_reserve_mib: ${LLM_HOST_GPU_RESERVE_MIB}
llm_host_require_physical_cores: ${LLM_HOST_REQUIRE_PHYSICAL_CORES}
llm_host_require_memory_mode: ${LLM_HOST_REQUIRE_MEMORY_MODE}
llm_host_require_nvidia: ${LLM_HOST_REQUIRE_NVIDIA}
llm_host_require_nvlink: ${LLM_HOST_REQUIRE_NVLINK}
llm_host_require_p2p: ${LLM_HOST_REQUIRE_P2P}
llm_host_install_support_packages: ${LLM_HOST_INSTALL_SUPPORT_PACKAGES}
EOF_VARS
  log "Prepared LLM host extra-vars: ${HOST_EXTRA_VARS_PATH}"
}

report.command() {
  local label="$1"
  shift
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "${label}" "$@"
}

run.read.only.preflight() {
  : > "${PREFLIGHT_REPORT_PATH}"
  log "Read-only LLM host preflight report: ${PREFLIGHT_REPORT_PATH}"
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "Shared GPU facts" /etc/ansible/debian/facts/gpu.yml
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "NVIDIA readiness facts" /etc/ansible/debian/facts/nvidia.yml
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "NVLink readiness facts" /etc/ansible/debian/facts/nvlink.yml
  report.command "CPU summary" lscpu
  report.command "CPU topology" lscpu --parse=CPU,SOCKET,CORE,ONLINE,NODE
  report.command "Host memory" sed -n '1,24p' /proc/meminfo
  report.command "NUMA topology" numactl --hardware
  report.command "NVIDIA runtime inventory" nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap --format=csv,noheader
  report.command "Persistent-memory resources" ipmctl show -memoryresources
  log "Preflight is read-only: it did not install packages, create directories, write facts, download models, or alter kernel, CPU, memory, swap, NVIDIA, or boot policy."
}

ensure.local.ansible.as.root() {
  runner.ensure.local.ansible
}

run.feature.playbook() {
  if [[ "${FEATURE_MODE}" == apply && "${LLM_HOST_INSTALL_SUPPORT_PACKAGES}" == true ]]; then
    runner.run.ansible.playbooks "${HOST_EXTRA_VARS_PATH}" "${PACKAGE_PLAYBOOK_PATH}" "${HOST_PLAYBOOK_PATH}"
  else
    runner.run.ansible.playbooks "${HOST_EXTRA_VARS_PATH}" "${HOST_PLAYBOOK_PATH}"
  fi
}

run.managed.mode() {
  runner.ensure.privileged.session || exit "${EXIT_BLOCKED}"
  source.release.common
  require.debian
  prepare.feature.files
  if [[ "${FEATURE_MODE}" == apply ]]; then
    [[ -x "${ANSIBLE_VENV_BIN}" ]] || ensure.local.ansible.as.root
  elif [[ ! -x "${ANSIBLE_VENV_BIN}" ]]; then
    log.error "validate never bootstraps an Ansible controller; managed Ansible is required at ${ANSIBLE_VENV_BIN}."
    exit "${EXIT_BLOCKED}"
  fi
  write.extra.vars.file
  if [[ "${FEATURE_MODE}" == apply && "${LLM_HOST_INSTALL_SUPPORT_PACKAGES}" == true ]]; then
    log "Installing the opt-in LLM host support package group before validation."
  else
    log "Running the LLM host playbook in ${FEATURE_MODE} mode without a package transaction."
  fi
  run.feature.playbook
}

main() {
  parse.arguments "$@"
  [[ "${SHOW_HELP}" -eq 0 ]] || { usage; return 0; }
  validate.configuration
  source.runner.common
  if [[ "${FEATURE_MODE}" == preflight ]]; then
    run.read.only.preflight
    return 0
  fi
  run.managed.mode
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
