#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/nvlink.sh
## Standalone CUDA, NVLink, and P2P validation runner.
## It refreshes NVIDIA-owned readiness facts through NVIDIA validate mode, then
## validates an existing NVIDIA/CUDA installation. It never installs drivers,
## CUDA toolkits, repositories, kernel modules, or boot configuration.
## EXAMPLE:

# Read-only inventory:
# wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | bash -s -- preflight
#
# Managed validation for dual RTX 3090 (SM 8.6), NVLink NV4, and strict P2P:
# wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | bash -s -- apply --gpu=all --require-exact-gpu-count=2 --require-compute-capability=8.6 --require-nvlink --expect-topology=NV4 --run-p2p-test --strict-p2p --p2p-buffer-mib=256 --p2p-iterations=20 --install-build-tools


set -euo pipefail

readonly EXIT_ADVISORY=2
readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.nvlink] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.nvlink][error] %s\n' "$*" >&2; }
log.warn() { printf '[setup.cli.nvlink][warn] %s\n' "$*" >&2; }

RUNNER_TMP_PARENT="${DEBIAN_RUNNER_TMP_PARENT:-/tmp}"
TMP_ROOT_DIR="${RUNNER_TMP_PARENT}"
TMP_DIR=""
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT=""
NVLINK_PLAYBOOK_PATH=""
NVLINK_EXTRA_VARS_PATH=""
PREFLIGHT_REPORT_PATH=""
LOCAL_RUNNER_HELPER="../runner.common.sh"
RUNNER_HELPER_NAME="runner.common.sh"
RUNNER_HELPER_URL="${PAGES_BASE_URL}/setup/${RUNNER_HELPER_NAME}"
RUNNER_HELPER_PATH=""
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""
REFRESH="${REFRESH:-0}"

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("cli/nvidia.yml" "cli/nvlink.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "tasks/gpu.inventory.yml"
  "tasks/nvidia.normalize-observations.yml"
  "files/gpu/gpu-inventory.py"
  "files/gpu/nvidia_topology.py"
  "files/nvlink/nvidia-p2p-verify.cu"
)
FEATURE_TEMPLATE_REFS=()

FEATURE_MODE="${DEBIAN_NVLINK_MODE:-preflight}"
NVLINK_GPU_SELECT="${DEBIAN_NVLINK_GPU_SELECT:-all}"
NVLINK_SELECT_GPUS="${DEBIAN_NVLINK_SELECT_GPUS:-0}"
NVLINK_REQUIRE_GPU_COUNT="${DEBIAN_NVLINK_REQUIRE_GPU_COUNT:-}"
NVLINK_REQUIRE_EXACT_GPU_COUNT="${DEBIAN_NVLINK_REQUIRE_EXACT_GPU_COUNT:-}"
NVLINK_REQUIRE_COMPUTE_CAPABILITIES="${DEBIAN_NVLINK_REQUIRE_COMPUTE_CAPABILITIES:-}"
NVLINK_REQUIRE_NVLINK="${DEBIAN_NVLINK_REQUIRE_NVLINK:-0}"
NVLINK_EXPECT_TOPOLOGY="${DEBIAN_NVLINK_EXPECT_TOPOLOGY:-}"
NVLINK_RUN_P2P_TEST="${DEBIAN_NVLINK_RUN_P2P_TEST:-0}"
NVLINK_STRICT_P2P="${DEBIAN_NVLINK_STRICT_P2P:-0}"
NVLINK_P2P_BUFFER_MIB="${DEBIAN_NVLINK_P2P_BUFFER_MIB:-256}"
NVLINK_P2P_ITERATIONS="${DEBIAN_NVLINK_P2P_ITERATIONS:-20}"
NVLINK_INSTALL_BUILD_TOOLS="${DEBIAN_NVLINK_INSTALL_BUILD_TOOLS:-1}"
NVLINK_GPU_SELECTION_SOURCE="auto"
SHOW_HELP=0
CLI_SEEN_VARIABLES=""
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

usage() {
  cat <<'EOF_USAGE'
Usage: nvlink.sh [preflight|apply|validate] [options]

Modes:
  preflight                 Read-only inventory and topology report (default).
  apply                     Refresh NVIDIA facts, optionally install source-neutral build tools, build, and validate.
  validate                  Refresh NVIDIA facts and re-run existing audited helpers; never install NVIDIA/CUDA packages.

Options:
  --gpu=all|<uuid-or-pci-list>
  --select-gpus
  --require-gpu-count=<minimum>
  --require-exact-gpu-count=<count>
  --require-compute-capability=<major.minor[,major.minor...]>
  --require-nvlink
  --expect-topology=NV4
  --run-p2p-test
  --strict-p2p
  --p2p-buffer-mib=<size>
  --p2p-iterations=<count>
  --install-build-tools|--no-install-build-tools
  --help

`--require-nvlink` makes a PCIe-only or inactive NVLink result fatal. Managed
runs first execute NVIDIA validate mode from NVIDIA-owned facts; this refresh
does not install or upgrade NVIDIA/CUDA packages. P2P diagnostics are opt-in;
`--strict-p2p` makes a requested P2P failure fatal.
EOF_USAGE
}

is.true() { case "${1:-}" in 1|true|TRUE|True|yes|YES|Yes|y|Y|on|ON|On) return 0 ;; *) return 1 ;; esac; }
is.boolean() { case "${1:-}" in 0|1|true|TRUE|True|false|FALSE|False|yes|YES|Yes|no|NO|No|y|Y|n|N|on|ON|On|off|OFF|Off) return 0 ;; *) return 1 ;; esac; }
bool.yaml() { is.true "${1:-0}" && printf true || printf false; }
yaml.quote() { local value="${1:-}"; value="${value//\\/\\\\}"; value="${value//\"/\\\"}"; printf '"%s"' "${value}"; }
invalid() { log.error "$*"; exit "${EXIT_USAGE}"; }

set.cli.value() {
  local variable="$1" environment_name="$2" value="$3"
  local environment_value="${!environment_name:-}" cli_value_variable="CLI_VALUE_${variable}"
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

set.cli.flag() { set.cli.value "$1" "$2" 1; }

parse.arguments() {
  local first=1 argument=""
  while (( "$#" )); do
    argument="$1"; shift
    if [[ "${first}" -eq 1 && "${argument}" != --* ]]; then
      set.cli.value FEATURE_MODE DEBIAN_NVLINK_MODE "${argument}"
      first=0
      continue
    fi
    first=0
    case "${argument}" in
      --help|-h) SHOW_HELP=1 ;;
      --gpu=*) set.cli.value NVLINK_GPU_SELECT DEBIAN_NVLINK_GPU_SELECT "${argument#*=}" ;;
      --select-gpus) set.cli.flag NVLINK_SELECT_GPUS DEBIAN_NVLINK_SELECT_GPUS ;;
      --require-gpu-count=*) set.cli.value NVLINK_REQUIRE_GPU_COUNT DEBIAN_NVLINK_REQUIRE_GPU_COUNT "${argument#*=}" ;;
      --require-exact-gpu-count=*) set.cli.value NVLINK_REQUIRE_EXACT_GPU_COUNT DEBIAN_NVLINK_REQUIRE_EXACT_GPU_COUNT "${argument#*=}" ;;
      --require-compute-capability=*) set.cli.value NVLINK_REQUIRE_COMPUTE_CAPABILITIES DEBIAN_NVLINK_REQUIRE_COMPUTE_CAPABILITIES "${argument#*=}" ;;
      --require-nvlink) set.cli.flag NVLINK_REQUIRE_NVLINK DEBIAN_NVLINK_REQUIRE_NVLINK ;;
      --expect-topology=*) set.cli.value NVLINK_EXPECT_TOPOLOGY DEBIAN_NVLINK_EXPECT_TOPOLOGY "${argument#*=}" ;;
      --run-p2p-test) set.cli.flag NVLINK_RUN_P2P_TEST DEBIAN_NVLINK_RUN_P2P_TEST ;;
      --strict-p2p) set.cli.flag NVLINK_STRICT_P2P DEBIAN_NVLINK_STRICT_P2P ;;
      --p2p-buffer-mib=*) set.cli.value NVLINK_P2P_BUFFER_MIB DEBIAN_NVLINK_P2P_BUFFER_MIB "${argument#*=}" ;;
      --p2p-iterations=*) set.cli.value NVLINK_P2P_ITERATIONS DEBIAN_NVLINK_P2P_ITERATIONS "${argument#*=}" ;;
      --install-build-tools) set.cli.flag NVLINK_INSTALL_BUILD_TOOLS DEBIAN_NVLINK_INSTALL_BUILD_TOOLS ;;
      --no-install-build-tools) set.cli.value NVLINK_INSTALL_BUILD_TOOLS DEBIAN_NVLINK_INSTALL_BUILD_TOOLS 0 ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

require.enum() { local label="$1" value="$2"; shift 2; local allowed=""; for allowed in "$@"; do [[ "${value}" == "${allowed}" ]] && return 0; done; invalid "Unsupported ${label}: ${value}"; }
validate.boolean() { is.boolean "$2" || invalid "$1 must be a boolean value."; }

validate.configuration() {
  require.enum mode "${FEATURE_MODE}" preflight apply validate
  validate.boolean DEBIAN_NVLINK_SELECT_GPUS "${NVLINK_SELECT_GPUS}"
  validate.boolean DEBIAN_NVLINK_REQUIRE_NVLINK "${NVLINK_REQUIRE_NVLINK}"
  validate.boolean DEBIAN_NVLINK_RUN_P2P_TEST "${NVLINK_RUN_P2P_TEST}"
  validate.boolean DEBIAN_NVLINK_STRICT_P2P "${NVLINK_STRICT_P2P}"
  validate.boolean DEBIAN_NVLINK_INSTALL_BUILD_TOOLS "${NVLINK_INSTALL_BUILD_TOOLS}"
  [[ -n "${NVLINK_GPU_SELECT}" ]] || invalid "GPU selection must be all or a comma-separated UUID/PCI list."
  if is.true "${NVLINK_SELECT_GPUS}" && [[ "|${CLI_SEEN_VARIABLES}|" == *"|NVLINK_GPU_SELECT|"* ]]; then
    invalid "--select-gpus cannot be combined with --gpu."
  fi
  for value in "${NVLINK_REQUIRE_GPU_COUNT}" "${NVLINK_REQUIRE_EXACT_GPU_COUNT}" "${NVLINK_P2P_BUFFER_MIB}" "${NVLINK_P2P_ITERATIONS}"; do
    [[ -z "${value}" || "${value}" =~ ^[0-9]+$ ]] || invalid "GPU counts and P2P sizes must be non-negative integers."
  done
  [[ "${NVLINK_P2P_BUFFER_MIB}" -gt 0 && "${NVLINK_P2P_ITERATIONS}" -gt 0 ]] || invalid "P2P buffer size and iterations must be greater than zero."
  if [[ -n "${NVLINK_REQUIRE_COMPUTE_CAPABILITIES}" ]]; then
    local capability=""; local -a capabilities=()
    IFS=',' read -r -a capabilities <<< "${NVLINK_REQUIRE_COMPUTE_CAPABILITIES}"
    for capability in "${capabilities[@]}"; do [[ "${capability}" =~ ^[0-9]+\.[0-9]+$ ]] || invalid "Compute capabilities must be comma-separated major.minor values."; done
  fi
  [[ -z "${NVLINK_EXPECT_TOPOLOGY}" || "${NVLINK_EXPECT_TOPOLOGY}" =~ ^NV[1-9][0-9]*$ ]] || invalid "Expected topology must be a positive NV# token such as NV4."
  if is.true "${NVLINK_STRICT_P2P}" && ! is.true "${NVLINK_RUN_P2P_TEST}"; then
    invalid "--strict-p2p requires --run-p2p-test."
  fi
}

interactive.gpu.selection() {
  command -v nvidia-smi >/dev/null 2>&1 || { log.error "--select-gpus requires nvidia-smi."; exit "${EXIT_BLOCKED}"; }
  [[ -r /dev/tty && -w /dev/tty ]] || { log.error "--select-gpus requires /dev/tty; use --gpu=GPU-...,GPU-... instead."; exit "${EXIT_USAGE}"; }
  local -a rows=() selections=() selected_rows=() uuids=()
  local row="" reply="" item="" index="" confirmation=""
  mapfile -t rows < <(nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,compute_cap --format=csv,noheader)
  ((${#rows[@]})) || { log.error "No physical NVIDIA GPUs were discovered."; exit "${EXIT_BLOCKED}"; }
  printf '\nAvailable NVIDIA GPUs:\n' >/dev/tty
  for index in "${!rows[@]}"; do printf '  %d) %s\n' "$((index + 1))" "${rows[$index]}" >/dev/tty; done
  printf 'Select exactly two comma-separated entries: ' >/dev/tty
  IFS= read -r reply </dev/tty || invalid "Unable to read GPU selection from /dev/tty."
  IFS=',' read -r -a selections <<< "${reply}"
  ((${#selections[@]} == 2)) || invalid "Exactly two GPU selections are required."
  [[ "${selections[0]//[[:space:]]/}" != "${selections[1]//[[:space:]]/}" ]] || invalid "The selected GPUs must be distinct."
  for item in "${selections[@]}"; do
    item="${item//[[:space:]]/}"
    [[ "${item}" =~ ^[0-9]+$ && "${item}" -ge 1 && "${item}" -le "${#rows[@]}" ]] || invalid "Invalid selection: ${item}"
    row="${rows[$((item - 1))]}"
    selected_rows+=("${row}")
    uuids+=("$(awk -F', ' '{print $3}' <<< "${row}")")
  done
  printf '\nSelected NVLink pair:\n  1) %s\n  2) %s\n' "${selected_rows[0]}" "${selected_rows[1]}" >/dev/tty
  printf 'Proceed with this exact pair? [y/N]: ' >/dev/tty
  IFS= read -r confirmation </dev/tty || invalid "Unable to read pair confirmation from /dev/tty."
  case "${confirmation}" in y|Y|yes|YES|Yes) ;; *) invalid "GPU pair selection was not confirmed." ;; esac
  NVLINK_GPU_SELECT="$(IFS=,; printf '%s' "${uuids[*]}")"
  NVLINK_GPU_SELECTION_SOURCE="interactive"
}

resolve.managed.gpu.pair() {
  local -a rows=() selectors=()

  [[ "${FEATURE_MODE}" != preflight ]] || return 0
  if is.true "${NVLINK_SELECT_GPUS}"; then
    interactive.gpu.selection
    return 0
  fi
  if [[ "${NVLINK_GPU_SELECT}" == all ]]; then
    command -v nvidia-smi >/dev/null 2>&1 || { log.error "--gpu=all requires nvidia-smi."; exit "${EXIT_BLOCKED}"; }
    mapfile -t rows < <(nvidia-smi --query-gpu=uuid --format=csv,noheader)
    ((${#rows[@]} == 2)) || {
      log.error "--gpu=all requires exactly two live physical NVIDIA GPUs; discovered ${#rows[@]}."
      log.error "Use --select-gpus or --gpu=<UUID-or-PCI>,<UUID-or-PCI>."
      exit "${EXIT_USAGE}"
    }
    NVLINK_GPU_SELECT="${rows[0]},${rows[1]}"
    NVLINK_GPU_SELECTION_SOURCE="auto"
    return 0
  fi

  IFS=',' read -r -a selectors <<< "${NVLINK_GPU_SELECT}"
  ((${#selectors[@]} == 2)) || invalid "Managed NVLink validation requires exactly two UUID or PCI selectors."
  selectors[0]="${selectors[0]//[[:space:]]/}"
  selectors[1]="${selectors[1]//[[:space:]]/}"
  [[ -n "${selectors[0]}" && -n "${selectors[1]}" ]] || invalid "Managed NVLink selectors cannot be empty."
  [[ "${selectors[0]}" != "${selectors[1]}" ]] || invalid "Managed NVLink selectors must be distinct."
  NVLINK_GPU_SELECT="${selectors[0]},${selectors[1]}"
  NVLINK_GPU_SELECTION_SOURCE="explicit"
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  NVLINK_EXTRA_VARS_PATH="${TMP_DIR}/cli.nvlink.extra-vars.yml"
  PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
  COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
}

source.runner.common() {
  local source_path="${BASH_SOURCE[0]:-}"
  local script_dir=""
  local local_helper=""
  local bootstrap_dir=""
  local repo_root=""

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
        runner.create.runtime nvlink "${RUNNER_TMP_PARENT}"
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

  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-nvlink.XXXXXX")"
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
    rm -f -- "${RUNNER_HELPER_PATH}"
    rmdir -- "${bootstrap_dir}" 2>/dev/null || true
    exit "${EXIT_BLOCKED}"
  }
  # shellcheck source=/tmp/devs-guide-nvlink.XXXXXX/runner.common.sh
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime nvlink "${bootstrap_dir}"
  configure.runtime.paths
}

source.release.common() {
  local local_setup_root=""

  if [[ -n "${RUNNER_LOCAL_REPO_ROOT}" ]]; then
    local_setup_root="${RUNNER_LOCAL_REPO_ROOT}/setup"
  fi
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

  if [[ -n "${RUNNER_LOCAL_REPO_ROOT}" ]]; then
    local_ansible_root="${RUNNER_LOCAL_REPO_ROOT}/ansible"
  fi
  runner.prepare.ansible.feature \
    "${local_ansible_root}" \
    "${PAGES_BASE_URL}/ansible" \
    "${PLAYBOOK_ROOT}" || {
      log.error "Unable to stage the NVLink Ansible manifest."
      exit "${EXIT_BLOCKED}"
    }
  NVLINK_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

write.extra.vars.file() {
  mkdir -p "${TMP_DIR}"
  cat > "${NVLINK_EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
nvlink_mode: $(yaml.quote "${FEATURE_MODE}")
nvlink_gpu_select: $(yaml.quote "${NVLINK_GPU_SELECT}")
nvlink_gpu_selection_source: $(yaml.quote "${NVLINK_GPU_SELECTION_SOURCE}")
nvlink_require_gpu_count: $(yaml.quote "${NVLINK_REQUIRE_GPU_COUNT}")
nvlink_require_exact_gpu_count: $(yaml.quote "${NVLINK_REQUIRE_EXACT_GPU_COUNT}")
nvlink_require_compute_capabilities: $(yaml.quote "${NVLINK_REQUIRE_COMPUTE_CAPABILITIES}")
nvlink_require_nvlink: $(bool.yaml "${NVLINK_REQUIRE_NVLINK}")
nvlink_expect_topology: $(yaml.quote "${NVLINK_EXPECT_TOPOLOGY}")
nvlink_run_p2p_test: $(bool.yaml "${NVLINK_RUN_P2P_TEST}")
nvlink_strict_p2p: $(bool.yaml "${NVLINK_STRICT_P2P}")
nvlink_p2p_buffer_mib: ${NVLINK_P2P_BUFFER_MIB}
nvlink_p2p_iterations: ${NVLINK_P2P_ITERATIONS}
nvlink_install_build_tools: $(bool.yaml "${NVLINK_INSTALL_BUILD_TOOLS}")
EOF_VARS
  log "Prepared NVLink extra-vars: ${NVLINK_EXTRA_VARS_PATH}"
}

ensure.local.ansible.as.root() {
  runner.ensure.local.ansible
}

run.feature.playbook() {
  runner.run.ansible.playbooks "${NVLINK_EXTRA_VARS_PATH}" "${NVLINK_PLAYBOOK_PATH}"
}

report.command() {
  local label="$1"
  shift
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "${label}" "$@"
}

report.text() {
  local label="$1"
  local path="$2"
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "${label}" "${path}"
}

run.read.only.preflight() {
  mkdir -p "${TMP_DIR}"; : > "${PREFLIGHT_REPORT_PATH}"
  log "Read-only NVLink preflight report: ${PREFLIGHT_REPORT_PATH}"
  report.text "NVIDIA prerequisite facts" /etc/ansible/debian/facts/nvidia.yml
  report.command "NVIDIA inventory" nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap --format=csv,noheader
  report.command "NVIDIA topology" nvidia-smi topo -m
  report.command "NVLink link status" nvidia-smi nvlink -s
  report.command "CUDA compiler" /usr/local/cuda/bin/nvcc --version
  report.command "CUDA compiler architectures" /usr/local/cuda/bin/nvcc --list-gpu-arch
  log "Preflight is read-only: it did not install packages, compile sources, create persistent logs, write facts, or alter NVIDIA state."
}

run.managed.mode() {
  runner.ensure.privileged.session || exit "${EXIT_BLOCKED}"
  source.release.common
  require.apt
  require.debian
  prepare.feature.files
  if [[ "${FEATURE_MODE}" == apply ]] && is.true "${NVLINK_RUN_P2P_TEST}" && is.true "${NVLINK_INSTALL_BUILD_TOOLS}"; then
    log "Proposed optional P2P build transaction: build-essential"
    apt-get -s --no-install-recommends install build-essential >/dev/null
  fi
  if [[ "${FEATURE_MODE}" == validate ]]; then
    [[ -x "${ANSIBLE_VENV_BIN}" ]] || { log.error "validate will not bootstrap Ansible; managed Ansible is missing at ${ANSIBLE_VENV_BIN}."; exit "${EXIT_BLOCKED}"; }
  else
    ensure.local.ansible.as.root
  fi
  write.extra.vars.file
  log "Running NVLink playbook in ${FEATURE_MODE} mode."
  run.feature.playbook
}

main() {
  parse.arguments "$@"
  [[ "${SHOW_HELP}" -eq 0 ]] || { usage; return 0; }
  validate.configuration
  resolve.managed.gpu.pair
  source.runner.common
  if is.true "${REFRESH}"; then
    log "REFRESH=1 requested; this invocation already uses a new empty runtime directory."
  fi
  if [[ "${FEATURE_MODE}" == preflight ]]; then run.read.only.preflight; return 0; fi
  run.managed.mode "$@"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
