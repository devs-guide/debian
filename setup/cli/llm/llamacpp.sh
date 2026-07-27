#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh
# Versioned llama.cpp source build and opt-in local-model smoke runner.
#
# wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
#   bash -s -- preflight --matrix-profile=b10075-icelake-sm86

set -euo pipefail

readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.llm.llamacpp] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.llm.llamacpp][error] %s\n' "$*" >&2; }
invalid() { log.error "$*"; exit "${EXIT_USAGE}"; }

RUNNER_TMP_PARENT="${DEBIAN_RUNNER_TMP_PARENT:-/tmp}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
LOCAL_RUNNER_HELPER="../../runner.common.sh"
RUNNER_HELPER_NAME="runner.common.sh"
RUNNER_HELPER_URL="${PAGES_BASE_URL}/setup/${RUNNER_HELPER_NAME}"
COMMON_HELPER_NAME="release.common.sh"

TMP_DIR=""
PLAYBOOK_ROOT=""
PACKAGE_PLAYBOOK_PATH=""
FEATURE_PLAYBOOK_PATH=""
EXTRA_VARS_PATH=""
PREFLIGHT_REPORT_PATH=""
SOURCE_PROFILE_HELPER_PATH=""
SOURCE_MATRIX_PATH=""
STAGED_SOURCE_PATH=""
RUNNER_HELPER_PATH=""
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("install.packages.yml" "cli/llm/llamacpp.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "files/llm/source-profile.py"
  "files/llm/llamacpp/compatibility-matrix.yml"
)
FEATURE_TEMPLATE_REFS=()
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

FEATURE_MODE="${DEBIAN_LLAMACPP_MODE:-preflight}"
MATRIX_PROFILE="${DEBIAN_LLAMACPP_MATRIX_PROFILE:-b10075-icelake-sm86}"
REPOSITORY_URL="${DEBIAN_LLAMACPP_REPOSITORY_URL:-https://github.com/ggml-org/llama.cpp.git}"
RELEASE="${DEBIAN_LLAMACPP_RELEASE:-b10075}"
COMMIT="${DEBIAN_LLAMACPP_COMMIT:-76f46ad29d61fd8c1401e8221842934bf62a6064}"
BUILD_PROFILE="${DEBIAN_LLAMACPP_BUILD_PROFILE:-icelake-sm86}"
CUDA_ARCHITECTURES="${DEBIAN_LLAMACPP_CUDA_ARCHITECTURES:-86}"
SOURCE_DIR="${DEBIAN_LLAMACPP_SOURCE_DIR:-}"
BUILD_DIR="${DEBIAN_LLAMACPP_BUILD_DIR:-}"
INSTALL_DIR="${DEBIAN_LLAMACPP_INSTALL_DIR:-}"
CLEAN_BUILD="${DEBIAN_LLAMACPP_CLEAN_BUILD:-false}"
INSTALL_BUILD_TOOLS="${DEBIAN_LLAMACPP_INSTALL_BUILD_TOOLS:-false}"
MODEL_PATH="${DEBIAN_LLAMACPP_MODEL_PATH:-}"
SMOKE_PROMPT="${DEBIAN_LLAMACPP_SMOKE_PROMPT:-Reply with exactly: llama.cpp smoke passed}"
MAX_TOKENS="${DEBIAN_LLAMACPP_MAX_TOKENS:-32}"
CTX_SIZE="${DEBIAN_LLAMACPP_CTX_SIZE:-2048}"
THREADS="${DEBIAN_LLAMACPP_THREADS:-36}"
THREADS_BATCH="${DEBIAN_LLAMACPP_THREADS_BATCH:-36}"
GPU_LAYERS="${DEBIAN_LLAMACPP_GPU_LAYERS:-auto}"
SPLIT_MODE="${DEBIAN_LLAMACPP_SPLIT_MODE:-layer}"
TENSOR_SPLIT="${DEBIAN_LLAMACPP_TENSOR_SPLIT:-1,1}"
FIT_TARGET="${DEBIAN_LLAMACPP_FIT_TARGET:-}"
OFFLINE="${DEBIAN_LLAMACPP_OFFLINE:-true}"
CHECK_TENSORS="${DEBIAN_LLAMACPP_CHECK_TENSORS:-true}"
SEED="${DEBIAN_LLAMACPP_SEED:-1}"
CPU_MOE="${DEBIAN_LLAMACPP_CPU_MOE:-false}"
N_CPU_MOE="${DEBIAN_LLAMACPP_N_CPU_MOE:-}"
SMOKE_TIMEOUT_SECONDS="${DEBIAN_LLAMACPP_SMOKE_TIMEOUT_SECONDS:-900}"
SHOW_HELP=0

usage() {
  cat <<'EOF_USAGE'
Usage: llamacpp.sh [preflight|apply|validate|smoke|upgrade] [options]

Modes:
  preflight                 Read-only reviewed-source and prerequisite report.
  apply                     Build and install the exact reviewed source.
  validate                  Validate the installed model-free runtime.
  smoke                     Run one bounded query against a local GGUF.
  upgrade                   Build a different reviewed matrix profile side-by-side.

Options:
  Source policy:
  --matrix-profile=PROFILE       Select an exact reviewed compatibility entry.
  --repository-url=HTTPS_URL     Credential-free HTTPS Git URL ending in .git.
  --release=TAG                  Exact reviewed upstream tag.
  --commit=FULL_40_CHAR_SHA      Lowercase full commit resolved from the tag.
  Build:
  --build-profile=PROFILE        Reviewed CPU/CUDA build-policy identifier.
  --cuda-architectures=LIST      Reviewed CUDA SM list; initial profile uses 86.
  --source-dir=/opt/src/llamacpp/PATH
                                 Optional constrained pristine source path.
  --build-dir=/opt/build/llamacpp/PATH
                                 Optional constrained mutable build path.
  --install-dir=/opt/llama.cpp/PATH
                                 Optional constrained versioned install path.
  --clean-build                  Recreate only the selected build directory.
  --install-build-tools          Install the opt-in llamacpp_build packages.
  --no-install-build-tools       Forbid a package transaction.
  Local-model smoke:
  --model=/absolute/model.gguf   Existing canonical non-symlink local GGUF.
  --prompt=TEXT                  One bounded deterministic prompt.
  --max-tokens=N                Maximum generated tokens; default 32.
  --ctx-size=N                  Context allocation; default 2048.
  --threads=N                   Decode CPU threads; default 36.
  --threads-batch=N             Batch CPU threads; default 36.
  --gpu-layers=auto|all|N       Value passed to llama-cli --n-gpu-layers.
  --split-mode=none|layer|row|tensor
                                 Multi-GPU tensor placement strategy.
  --tensor-split=RATIOS         Comma-separated per-GPU ratios; default 1,1.
  --fit-target=MIB_LIST         Optional per-device fit target when advertised.
  --offline                     Require local-only model behavior.
  --check-tensors               Validate tensor data while loading.
  --seed=N                      Deterministic generation seed; default 1.
  --cpu-moe                     Move all MoE experts to CPU when advertised.
  --n-cpu-moe=N                Move the first N MoE layers to CPU.
  --smoke-timeout-seconds=N     Wall-clock limit; default 900.
  --help                        Print this help without staging.

Reviewed apply example:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
    bash -s -- apply \
      --matrix-profile=b10075-icelake-sm86 \
      --repository-url=https://github.com/ggml-org/llama.cpp.git \
      --release=b10075 \
      --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
      --build-profile=icelake-sm86 \
      --cuda-architectures=86 \
      --source-dir=/opt/src/llamacpp/b10075-icelake-sm86 \
      --build-dir=/opt/build/llamacpp/b10075-icelake-sm86 \
      --install-dir=/opt/llama.cpp/b10075-icelake-sm86 \
      --install-build-tools

Remote local-model smoke example:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
    bash -s -- smoke \
      --matrix-profile=b10075-icelake-sm86 \
      --repository-url=https://github.com/ggml-org/llama.cpp.git \
      --release=b10075 \
      --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
      --build-profile=icelake-sm86 \
      --cuda-architectures=86 \
      --source-dir=/opt/src/llamacpp/b10075-icelake-sm86 \
      --build-dir=/opt/build/llamacpp/b10075-icelake-sm86 \
      --install-dir=/opt/llama.cpp/b10075-icelake-sm86 \
      --model=/models/gguf/smoke/model.gguf \
      --prompt="Reply with exactly: llama.cpp smoke passed" \
      --max-tokens=32 \
      --ctx-size=2048 \
      --threads=36 \
      --threads-batch=36 \
      --gpu-layers=auto \
      --split-mode=layer \
      --tensor-split=1,1 \
      --offline \
      --check-tensors \
      --seed=1 \
      --smoke-timeout-seconds=900

Repository URLs and full commits are accepted as inputs, but apply/upgrade
proceed only when the complete tuple matches the staged compatibility matrix.
The runner never downloads a model.
EOF_USAGE
}

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
      --matrix-profile=*) MATRIX_PROFILE="${argument#*=}" ;;
      --repository-url=*) REPOSITORY_URL="${argument#*=}" ;;
      --release=*) RELEASE="${argument#*=}" ;;
      --commit=*) COMMIT="${argument#*=}" ;;
      --build-profile=*) BUILD_PROFILE="${argument#*=}" ;;
      --cuda-architectures=*) CUDA_ARCHITECTURES="${argument#*=}" ;;
      --source-dir=*) SOURCE_DIR="${argument#*=}" ;;
      --build-dir=*) BUILD_DIR="${argument#*=}" ;;
      --install-dir=*) INSTALL_DIR="${argument#*=}" ;;
      --clean-build) CLEAN_BUILD=true ;;
      --install-build-tools) INSTALL_BUILD_TOOLS=true ;;
      --no-install-build-tools) INSTALL_BUILD_TOOLS=false ;;
      --model=*) MODEL_PATH="${argument#*=}" ;;
      --prompt=*) SMOKE_PROMPT="${argument#*=}" ;;
      --max-tokens=*) MAX_TOKENS="${argument#*=}" ;;
      --ctx-size=*) CTX_SIZE="${argument#*=}" ;;
      --threads=*) THREADS="${argument#*=}" ;;
      --threads-batch=*) THREADS_BATCH="${argument#*=}" ;;
      --gpu-layers=*) GPU_LAYERS="${argument#*=}" ;;
      --split-mode=*) SPLIT_MODE="${argument#*=}" ;;
      --tensor-split=*) TENSOR_SPLIT="${argument#*=}" ;;
      --fit-target=*) FIT_TARGET="${argument#*=}" ;;
      --offline) OFFLINE=true ;;
      --check-tensors) CHECK_TENSORS=true ;;
      --seed=*) SEED="${argument#*=}" ;;
      --cpu-moe) CPU_MOE=true ;;
      --n-cpu-moe=*) N_CPU_MOE="${argument#*=}" ;;
      --smoke-timeout-seconds=*) SMOKE_TIMEOUT_SECONDS="${argument#*=}" ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

validate.path.override() {
  local value="$1" prefix="$2" label="$3"
  [[ -z "${value}" ]] && return 0
  [[ "${value}" == "${prefix}/"* && "${value}" =~ ^/[A-Za-z0-9._/+~-]+$ && "${value}" != *".."* ]] ||
    invalid "${label} must be an absolute child of ${prefix}."
}

validate.configuration() {
  case "${FEATURE_MODE}" in preflight|apply|validate|smoke|upgrade) ;; *) invalid "Unsupported mode: ${FEATURE_MODE}" ;; esac
  [[ "${MATRIX_PROFILE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid matrix profile."
  [[ "${RELEASE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid release."
  [[ "${BUILD_PROFILE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid build profile."
  [[ "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || invalid "--commit must be a lowercase full 40-character SHA."
  [[ "${CUDA_ARCHITECTURES}" =~ ^[0-9]+([,;][0-9]+)*$ ]] || invalid "Invalid CUDA architecture list."
  [[ "${REPOSITORY_URL}" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._+~-]+)+[.]git$ ]] ||
    invalid "--repository-url must be a credential-free HTTPS Git URL ending in .git."
  [[ "${REPOSITORY_URL}" != *"@"* && "${REPOSITORY_URL}" != *"?"* && "${REPOSITORY_URL}" != *"#"* ]] ||
    invalid "Repository credentials, queries, and fragments are not accepted."
  validate.path.override "${SOURCE_DIR}" /opt/src/llamacpp --source-dir
  validate.path.override "${BUILD_DIR}" /opt/build/llamacpp --build-dir
  validate.path.override "${INSTALL_DIR}" /opt/llama.cpp --install-dir
  for value in "${MAX_TOKENS}" "${CTX_SIZE}" "${THREADS}" "${THREADS_BATCH}" "${SEED}" "${SMOKE_TIMEOUT_SECONDS}"; do
    [[ "${value}" =~ ^[0-9]+$ ]] || invalid "Smoke limits and seed must be non-negative integers."
  done
  ((10#${MAX_TOKENS} > 0 && 10#${CTX_SIZE} > 0 && 10#${THREADS} > 0 && 10#${THREADS_BATCH} > 0 && 10#${SMOKE_TIMEOUT_SECONDS} > 0)) ||
    invalid "Token, context, thread, and timeout limits must be positive."
  [[ "${GPU_LAYERS}" =~ ^(auto|all|[0-9]+)$ ]] || invalid "Invalid --gpu-layers value."
  case "${SPLIT_MODE}" in none|layer|row|tensor) ;; *) invalid "Invalid --split-mode value." ;; esac
  [[ "${TENSOR_SPLIT}" =~ ^[0-9]+([.][0-9]+)?(,[0-9]+([.][0-9]+)?)*$ ]] || invalid "Invalid --tensor-split value."
  [[ -z "${FIT_TARGET}" || "${FIT_TARGET}" =~ ^[0-9]+(,[0-9]+)*$ ]] || invalid "Invalid --fit-target value."
  [[ -z "${N_CPU_MOE}" || "${N_CPU_MOE}" =~ ^[0-9]+$ ]] || invalid "Invalid --n-cpu-moe value."
  [[ "${CPU_MOE}" != true || -z "${N_CPU_MOE}" ]] || invalid "--cpu-moe and --n-cpu-moe are mutually exclusive."
  [[ "${FEATURE_MODE}" != smoke || "${MODEL_PATH}" == /* ]] || invalid "smoke requires an absolute --model path."
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  EXTRA_VARS_PATH="${TMP_DIR}/cli.llm.llamacpp.extra-vars.yml"
  PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
  COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
  SOURCE_PROFILE_HELPER_PATH="${PLAYBOOK_ROOT}/files/llm/source-profile.py"
  SOURCE_MATRIX_PATH="${PLAYBOOK_ROOT}/files/llm/llamacpp/compatibility-matrix.yml"
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
        source "${RUNNER_HELPER_PATH}"
        runner.create.runtime llm-llamacpp "${RUNNER_TMP_PARENT}"
        configure.runtime.paths
        return
      fi
      ;;
  esac
  command -v wget >/dev/null 2>&1 || { log.error "wget is required."; exit "${EXIT_BLOCKED}"; }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-llm-llamacpp.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  log "Fetching shared runner helper: ${RUNNER_HELPER_URL}"
  wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" && [[ -s "${RUNNER_HELPER_PATH}" ]] ||
    { log.error "Failed to fetch ${RUNNER_HELPER_URL}"; exit "${EXIT_BLOCKED}"; }
  bash -n "${RUNNER_HELPER_PATH}" || { log.error "Downloaded runner helper is invalid."; exit "${EXIT_BLOCKED}"; }
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime llm-llamacpp "${bootstrap_dir}"
  configure.runtime.paths
}

source.release.common() {
  local local_setup_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_setup_root="${RUNNER_LOCAL_REPO_ROOT}/setup"
  runner.source.release.common "${local_setup_root}" "${PAGES_BASE_URL}/setup" "${TMP_DIR}" "${COMMON_HELPER_NAME}" ||
    { log.error "Unable to stage the shared release helper."; exit "${EXIT_BLOCKED}"; }
}

prepare.feature.files() {
  local local_ansible_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_ansible_root="${RUNNER_LOCAL_REPO_ROOT}/ansible"
  runner.prepare.ansible.feature "${local_ansible_root}" "${PAGES_BASE_URL}/ansible" "${PLAYBOOK_ROOT}" ||
    { log.error "Unable to stage the llama.cpp feature."; exit "${EXIT_BLOCKED}"; }
  PACKAGE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[0]}"
  FEATURE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

validate.reviewed.source() {
  python3 "${SOURCE_PROFILE_HELPER_PATH}" \
    --matrix "${SOURCE_MATRIX_PATH}" \
    --feature llamacpp \
    --profile "${MATRIX_PROFILE}" \
    --repository-url "${REPOSITORY_URL}" \
    --release "${RELEASE}" \
    --commit "${COMMIT}" >/dev/null ||
    { log.error "The requested llama.cpp source tuple is not reviewed."; exit "${EXIT_BLOCKED}"; }
}

stage.reviewed.source() {
  local resolved=""
  command -v git >/dev/null 2>&1 || { log.error "git is required to stage reviewed source."; exit "${EXIT_BLOCKED}"; }
  STAGED_SOURCE_PATH="${TMP_DIR}/upstream/llamacpp"
  mkdir -p "$(dirname "${STAGED_SOURCE_PATH}")"
  git init -q "${STAGED_SOURCE_PATH}"
  git -C "${STAGED_SOURCE_PATH}" remote add origin "${REPOSITORY_URL}"
  log "Fetching reviewed llama.cpp tag ${RELEASE} as the invoking user."
  git -C "${STAGED_SOURCE_PATH}" fetch -q --depth=1 origin "refs/tags/${RELEASE}:refs/tags/${RELEASE}"
  resolved="$(git -C "${STAGED_SOURCE_PATH}" rev-list -n 1 "refs/tags/${RELEASE}")"
  [[ "${resolved}" == "${COMMIT}" ]] ||
    { log.error "Tag ${RELEASE} resolves to ${resolved}, not reviewed commit ${COMMIT}."; exit "${EXIT_BLOCKED}"; }
  git -C "${STAGED_SOURCE_PATH}" -c advice.detachedHead=false checkout -q --detach "${COMMIT}"
  [[ -z "$(git -C "${STAGED_SOURCE_PATH}" status --porcelain)" ]] ||
    { log.error "Staged llama.cpp source is unexpectedly dirty."; exit "${EXIT_BLOCKED}"; }
}

write.extra.vars.file() {
  local model_b64="" prompt_b64=""
  model_b64="$(printf '%s' "${MODEL_PATH}" | base64 | tr -d '\n')"
  prompt_b64="$(printf '%s' "${SMOKE_PROMPT}" | base64 | tr -d '\n')"
  cat > "${EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_catalog_url: "${PAGES_BASE_URL}/ansible/packages.yml"
package_catalog_filename: "packages.yml"
package_group_allowlist: ["llamacpp_build"]
package_group_overrides:
  llamacpp_build: true
llamacpp_mode: "${FEATURE_MODE}"
llamacpp_matrix_profile: "${MATRIX_PROFILE}"
llamacpp_repository_url: "${REPOSITORY_URL}"
llamacpp_release: "${RELEASE}"
llamacpp_commit: "${COMMIT}"
llamacpp_build_profile: "${BUILD_PROFILE}"
llamacpp_cuda_architectures: "${CUDA_ARCHITECTURES}"
llamacpp_source_dir_override: "${SOURCE_DIR}"
llamacpp_build_dir_override: "${BUILD_DIR}"
llamacpp_install_dir_override: "${INSTALL_DIR}"
llamacpp_clean_build: ${CLEAN_BUILD}
llamacpp_install_build_tools: ${INSTALL_BUILD_TOOLS}
llamacpp_staged_source_path: "${STAGED_SOURCE_PATH}"
llamacpp_model_path_b64: "${model_b64}"
llamacpp_smoke_prompt_b64: "${prompt_b64}"
llamacpp_max_tokens: ${MAX_TOKENS}
llamacpp_ctx_size: ${CTX_SIZE}
llamacpp_threads: ${THREADS}
llamacpp_threads_batch: ${THREADS_BATCH}
llamacpp_gpu_layers: "${GPU_LAYERS}"
llamacpp_split_mode: "${SPLIT_MODE}"
llamacpp_tensor_split: "${TENSOR_SPLIT}"
llamacpp_fit_target: "${FIT_TARGET}"
llamacpp_offline: ${OFFLINE}
llamacpp_check_tensors: ${CHECK_TENSORS}
llamacpp_seed: ${SEED}
llamacpp_cpu_moe: ${CPU_MOE}
llamacpp_n_cpu_moe: "${N_CPU_MOE}"
llamacpp_smoke_timeout_seconds: ${SMOKE_TIMEOUT_SECONDS}
EOF_VARS
}

run.preflight() {
  : > "${PREFLIGHT_REPORT_PATH}"
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "LLM host facts" /etc/ansible/debian/facts/llm-host.yml
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "NVIDIA facts" /etc/ansible/debian/facts/nvidia.yml
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Reviewed llama.cpp tag" \
    git ls-remote --tags "${REPOSITORY_URL}" "refs/tags/${RELEASE}" "refs/tags/${RELEASE}^{}"
  printf '\n## Reviewed source policy\nprofile=%s\nrepository=%s\nrelease=%s\ncommit=%s\n' \
    "${MATRIX_PROFILE}" "${REPOSITORY_URL}" "${RELEASE}" "${COMMIT}" | tee -a "${PREFLIGHT_REPORT_PATH}"
  log "Preflight is read-only: no source was cloned, package installed, directory created, model read, or fact written."
}

run.managed() {
  if [[ "${FEATURE_MODE}" == apply || "${FEATURE_MODE}" == upgrade ]]; then
    stage.reviewed.source
  fi
  runner.ensure.privileged.session || exit "${EXIT_BLOCKED}"
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || runner.ensure.local.ansible
  write.extra.vars.file
  if [[ ("${FEATURE_MODE}" == apply || "${FEATURE_MODE}" == upgrade) && "${INSTALL_BUILD_TOOLS}" == true ]]; then
    runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${PACKAGE_PLAYBOOK_PATH}" "${FEATURE_PLAYBOOK_PATH}"
  else
    runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${FEATURE_PLAYBOOK_PATH}"
  fi
}

main() {
  parse.arguments "$@"
  [[ "${SHOW_HELP}" -eq 0 ]] || { usage; return 0; }
  validate.configuration
  source.runner.common
  source.release.common
  require.debian
  prepare.feature.files
  validate.reviewed.source
  if [[ "${FEATURE_MODE}" == preflight ]]; then
    run.preflight
  else
    run.managed
  fi
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
