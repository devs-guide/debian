#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/gpu.sh
# Shared GPU inventory runner. It records hardware/runtime observations only;
# it never installs drivers, CUDA, packages, kernel modules, or repositories.
#
# Refresh the canonical GPU inventory after NVIDIA/CUDA validation. This records
# PCI identity for detected NVIDIA, AMD, and Intel devices; NVIDIA devices also
# record UUID, compute capability, and topology labels from nvidia-smi topo -m.
#
# wget -qO- https://devs-guide.github.io/debian/setup/cli/gpu.sh | \
#   bash -s -- apply \
#     --vendor=auto

set -euo pipefail

readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.gpu] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.gpu][error] %s\n' "$*" >&2; }

RUNNER_TMP_PARENT="${DEBIAN_RUNNER_TMP_PARENT:-/tmp}"
TMP_DIR=""
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT=""
PLAYBOOK_GROUP_VARS_DIR=""
GPU_PLAYBOOK_REL="cli/gpu.yml"
GPU_PLAYBOOK_PATH=""
GPU_EXTRA_VARS_PATH=""
PREFLIGHT_REPORT_PATH=""
LOCAL_RUNNER_HELPER="../runner.common.sh"
RUNNER_HELPER_NAME="runner.common.sh"
RUNNER_HELPER_URL="${PAGES_BASE_URL}/setup/${RUNNER_HELPER_NAME}"
RUNNER_HELPER_PATH=""
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("cli/gpu.yml")
RUNTIME_SUPPORT_REFS=(
  "tasks/gpu.inventory.yml"
  "files/gpu/gpu-inventory.py"
  "files/gpu/nvidia_topology.py"
)
FEATURE_TEMPLATE_REFS=()

FEATURE_MODE="${DEBIAN_GPU_MODE:-preflight}"
GPU_VENDOR="${DEBIAN_GPU_VENDOR:-auto}"
SHOW_HELP=0
declare -a FEATURE_GROUP_VARS_ARGS=()

usage() {
  cat <<'EOF_USAGE'
Usage: gpu.sh [preflight|apply|validate] [options]

Modes:
  preflight                 Read-only PCI/runtime/topology report (default).
  apply                     Refresh /etc/ansible/debian/facts/gpu.yml.
  validate                  Refresh the same fact.

Options:
  --vendor=auto|nvidia
  --help

V1 enriches NVIDIA devices with nvidia-smi UUID, CUDA capability, and topology
labels. AMD and Intel devices are recorded from PCI inventory only.
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
      --vendor=*) GPU_VENDOR="${argument#*=}" ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

validate.configuration() {
  case "${FEATURE_MODE}" in preflight|apply|validate) ;; *) invalid "Unsupported mode: ${FEATURE_MODE}" ;; esac
  case "${GPU_VENDOR}" in auto|nvidia) ;; *) invalid "Unsupported vendor: ${GPU_VENDOR}" ;; esac
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
  GPU_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${GPU_PLAYBOOK_REL}"
  GPU_EXTRA_VARS_PATH="${TMP_DIR}/cli.gpu.extra-vars.yml"
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
        repo_root="$(cd "${script_dir}/../.." && pwd -P)"
        RUNNER_LOCAL_REPO_ROOT="${repo_root}"
        RUNNER_HELPER_PATH="$(cd "$(dirname "${local_helper}")" && pwd)/$(basename "${local_helper}")"
        # shellcheck source=setup/runner.common.sh
        source "${RUNNER_HELPER_PATH}"
        runner.create.runtime gpu "${RUNNER_TMP_PARENT}"
        configure.runtime.paths
        return
      fi
      ;;
  esac
  command -v wget >/dev/null 2>&1 || { log.error "Cannot fetch the runner helper because wget is unavailable."; exit "${EXIT_BLOCKED}"; }
  [[ "${RUNNER_TMP_PARENT}" == /* && "${RUNNER_TMP_PARENT}" != / && -d "${RUNNER_TMP_PARENT}" && -w "${RUNNER_TMP_PARENT}" ]] || {
    log.error "Runner temporary parent must be an existing writable absolute directory other than /: ${RUNNER_TMP_PARENT}"
    exit "${EXIT_BLOCKED}"
  }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-gpu.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  log "Fetching shared runner helper: ${RUNNER_HELPER_URL}"
  if ! wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" || [[ ! -s "${RUNNER_HELPER_PATH}" ]]; then
    log.error "Failed to fetch shared runner helper: ${RUNNER_HELPER_URL}"
    rm -f -- "${RUNNER_HELPER_PATH}"
    rmdir -- "${bootstrap_dir}" 2>/dev/null || true
    exit "${EXIT_BLOCKED}"
  fi
  bash -n "${RUNNER_HELPER_PATH}" || { log.error "Downloaded runner helper failed shell syntax validation."; exit "${EXIT_BLOCKED}"; }
  # shellcheck source=/tmp/devs-guide-gpu.XXXXXX/runner.common.sh
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime gpu "${bootstrap_dir}"
  configure.runtime.paths
}

source.release.common() {
  local local_setup_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_setup_root="${RUNNER_LOCAL_REPO_ROOT}/setup"
  runner.stage.manifest "${local_setup_root}" "${PAGES_BASE_URL}/setup" "${TMP_DIR}" "shared release helper" "${COMMON_HELPER_NAME}" || {
    log.error "Unable to stage the shared release helper."
    exit "${EXIT_BLOCKED}"
  }
  bash -n "${COMMON_HELPER_PATH}" || { log.error "The staged release helper failed shell syntax validation."; exit "${EXIT_BLOCKED}"; }
  # shellcheck source=/tmp/devs-guide-gpu.XXXXXX/release.common.sh
  source "${COMMON_HELPER_PATH}"
}

reset.feature.extra.vars.args() {
  FEATURE_GROUP_VARS_ARGS=()
  local file=""
  for file in "${GROUP_VARS_FILES[@]}"; do
    [[ -s "${PLAYBOOK_GROUP_VARS_DIR}/${file}" ]] || { log.error "Staged group variables are unavailable: ${PLAYBOOK_GROUP_VARS_DIR}/${file}"; exit "${EXIT_BLOCKED}"; }
    FEATURE_GROUP_VARS_ARGS+=(-e "@${PLAYBOOK_GROUP_VARS_DIR}/${file}")
  done
}

prepare.feature.files() {
  local local_ansible_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_ansible_root="${RUNNER_LOCAL_REPO_ROOT}/ansible"
  runner.stage.ansible.feature "${local_ansible_root}" "${PAGES_BASE_URL}/ansible" "${PLAYBOOK_ROOT}" || {
    log.error "Unable to stage the shared GPU Ansible manifest."
    exit "${EXIT_BLOCKED}"
  }
  reset.feature.extra.vars.args
}

write.extra.vars.file() {
  cat > "${GPU_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
gpu_mode: "${FEATURE_MODE}"
gpu_vendor: "${GPU_VENDOR}"
EOF_VARS
  log "Prepared shared GPU extra-vars: ${GPU_EXTRA_VARS_PATH}"
}

run.feature.playbook() {
  runner.run.as.root /usr/bin/env -i \
    HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp \
    "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" \
      -e "@${GPU_EXTRA_VARS_PATH}" "${GPU_PLAYBOOK_PATH}"
}

report.command() { local label="$1"; shift; { printf '\n## %s\n' "${label}"; "$@" 2>&1 || true; } | tee -a "${PREFLIGHT_REPORT_PATH}"; }

run.read.only.preflight() {
  : > "${PREFLIGHT_REPORT_PATH}"
  log "Read-only shared GPU preflight report: ${PREFLIGHT_REPORT_PATH}"
  report.command "PCI display/accelerator inventory" lspci -Dnnk
  report.command "NVIDIA runtime inventory" nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap --format=csv,noheader
  report.command "NVIDIA topology labels" nvidia-smi topo -m
  log "Preflight is read-only: it did not install packages, drivers, CUDA, kernel modules, repositories, or write GPU facts."
}

run.managed.mode() {
  runner.ensure.privileged.session || exit "${EXIT_BLOCKED}"
  source.release.common
  require.debian
  prepare.feature.files
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || {
    log.error "${FEATURE_MODE} never bootstraps or installs an Ansible controller; managed Ansible is required at ${ANSIBLE_VENV_BIN}."
    exit "${EXIT_BLOCKED}"
  }
  write.extra.vars.file
  log "Running shared GPU playbook in ${FEATURE_MODE} mode."
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
