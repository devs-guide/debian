#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh
# Exact-source KTransformers, KT-Kernel, and SGLang-KT toolchain runner.
#
# wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
#   bash -s -- preflight --matrix-profile=v0.6.3-icelake-sm86-source

set -euo pipefail

readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64

log() { printf '[setup.cli.llm.ktransformers] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.llm.ktransformers][error] %s\n' "$*" >&2; }
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
STAGED_PYTHON_ARCHIVE=""
PROFILE_JSON=""
RUNNER_HELPER_PATH=""
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("install.packages.yml" "cli/llm/ktransformers.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "files/llm/source-profile.py"
  "files/llm/ktransformers/compatibility-matrix.yml"
)
FEATURE_TEMPLATE_REFS=()
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

FEATURE_MODE="${DEBIAN_KTRANSFORMERS_MODE:-preflight}"
MATRIX_PROFILE="${DEBIAN_KTRANSFORMERS_MATRIX_PROFILE:-v0.6.3-icelake-sm86-source}"
REPOSITORY_URL="${DEBIAN_KTRANSFORMERS_REPOSITORY_URL:-https://github.com/kvcache-ai/ktransformers.git}"
RELEASE="${DEBIAN_KTRANSFORMERS_RELEASE:-v0.6.3}"
COMMIT="${DEBIAN_KTRANSFORMERS_COMMIT:-ce7c3ddbe93f7ac1f992375eed54058bbc512646}"
SGLANG_REPOSITORY_URL="${DEBIAN_KTRANSFORMERS_SGLANG_REPOSITORY_URL:-https://github.com/kvcache-ai/sglang.git}"
SGLANG_COMMIT="${DEBIAN_KTRANSFORMERS_SGLANG_COMMIT:-8b636f9008dbad58c0a8e481b03e794739e6c146}"
INSTALL_PROFILE="${DEBIAN_KTRANSFORMERS_INSTALL_PROFILE:-source}"
PYTHON_VERSION="${DEBIAN_KTRANSFORMERS_PYTHON_VERSION:-3.12.3}"
WHEELHOUSE="${DEBIAN_KTRANSFORMERS_WHEELHOUSE:-}"
ALLOW_ONLINE_DEPENDENCIES="${DEBIAN_KTRANSFORMERS_ALLOW_ONLINE_DEPENDENCIES:-false}"
CUDA_ARCHITECTURES="${DEBIAN_KTRANSFORMERS_CUDA_ARCHITECTURES:-86}"
CPU_PROFILE="${DEBIAN_KTRANSFORMERS_CPU_PROFILE:-icelake-avx512-vnni}"
SOURCE_DIR="${DEBIAN_KTRANSFORMERS_SOURCE_DIR:-}"
BUILD_DIR="${DEBIAN_KTRANSFORMERS_BUILD_DIR:-}"
INSTALL_DIR="${DEBIAN_KTRANSFORMERS_INSTALL_DIR:-}"
CLEAN_BUILD="${DEBIAN_KTRANSFORMERS_CLEAN_BUILD:-false}"
INSTALL_BUILD_TOOLS="${DEBIAN_KTRANSFORMERS_INSTALL_BUILD_TOOLS:-false}"
SHOW_HELP=0

usage() {
  cat <<'EOF_USAGE'
Usage: ktransformers.sh [preflight|apply|validate|upgrade] [options]

Modes:
  preflight                 Read-only reviewed-source and prerequisite report.
  apply                     Build and install an exact reviewed source profile.
  validate                  Validate the installed model-free runtime.
  upgrade                   Build another reviewed profile side-by-side.

Options:
  Source policy:
  --matrix-profile=PROFILE       Select an exact reviewed compatibility entry.
  --repository-url=HTTPS_URL     Exact KTransformers HTTPS Git repository.
  --release=TAG                  Exact reviewed KTransformers tag.
  --commit=FULL_40_CHAR_SHA      Lowercase full KTransformers commit.
  --sglang-repository-url=URL    Exact reviewed SGLang-KT HTTPS repository.
  --sglang-commit=FULL_SHA       Lowercase full SGLang submodule commit.
  Toolchain:
  --install-profile=source       Use the reviewed source-build workflow.
  --python-version=X.Y.Z         Exact matrix-approved Python 3.12 patch.
  --wheelhouse=/absolute/path    Approved local wheel dependency directory.
  --allow-online-dependencies    Explicitly permit bootstrap dependency access.
  --no-online-dependencies       Forbid online Python dependency resolution.
  --cuda-architectures=LIST      Reviewed CUDA SM list; initial profile uses 86.
  --cpu-profile=PROFILE          Reviewed CPU instruction-policy identifier.
  --source-dir=/opt/src/ktransformers/PATH
                                 Optional constrained pristine source path.
  --build-dir=/opt/build/ktransformers/PATH
                                 Optional constrained mutable worktree path.
  --install-dir=/opt/venvs/ktransformers-PATH
                                 Optional constrained virtual environment.
  --clean-build                  Recreate selected build and unpromoted venv.
  --install-build-tools          Install opt-in ktransformers_build packages.
  --no-install-build-tools       Forbid a package transaction.
  --help                         Print this help without staging.

Reviewed source-build example:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
    bash -s -- apply \
      --matrix-profile=v0.6.3-icelake-sm86-source \
      --repository-url=https://github.com/kvcache-ai/ktransformers.git \
      --release=v0.6.3 \
      --commit=ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
      --sglang-repository-url=https://github.com/kvcache-ai/sglang.git \
      --sglang-commit=8b636f9008dbad58c0a8e481b03e794739e6c146 \
      --install-profile=source \
      --python-version=3.12.3 \
      --allow-online-dependencies \
      --cuda-architectures=86 \
      --cpu-profile=icelake-avx512-vnni \
      --source-dir=/opt/src/ktransformers/v0.6.3-icelake-sm86-source \
      --build-dir=/opt/build/ktransformers/v0.6.3-icelake-sm86-source \
      --install-dir=/opt/venvs/ktransformers-v0.6.3-icelake-sm86-source \
      --install-build-tools

Model-free validation example:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
    sudo bash -s -- validate \
      --matrix-profile=v0.6.3-icelake-sm86-source \
      --repository-url=https://github.com/kvcache-ai/ktransformers.git \
      --release=v0.6.3 \
      --commit=ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
      --sglang-repository-url=https://github.com/kvcache-ai/sglang.git \
      --sglang-commit=8b636f9008dbad58c0a8e481b03e794739e6c146 \
      --install-profile=source \
      --python-version=3.12.3 \
      --no-online-dependencies \
      --cuda-architectures=86 \
      --cpu-profile=icelake-avx512-vnni \
      --source-dir=/opt/src/ktransformers/v0.6.3-icelake-sm86-source \
      --build-dir=/opt/build/ktransformers/v0.6.3-icelake-sm86-source \
      --install-dir=/opt/venvs/ktransformers-v0.6.3-icelake-sm86-source \
      --no-install-build-tools

Repository URLs and full commits are first-class inputs. Managed builds
proceed only when the complete KTransformers and SGLang tuple matches the
staged compatibility matrix. Models are never downloaded or loaded here.
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
      --sglang-repository-url=*) SGLANG_REPOSITORY_URL="${argument#*=}" ;;
      --sglang-commit=*) SGLANG_COMMIT="${argument#*=}" ;;
      --install-profile=*) INSTALL_PROFILE="${argument#*=}" ;;
      --python-version=*) PYTHON_VERSION="${argument#*=}" ;;
      --wheelhouse=*) WHEELHOUSE="${argument#*=}" ;;
      --allow-online-dependencies) ALLOW_ONLINE_DEPENDENCIES=true ;;
      --no-online-dependencies) ALLOW_ONLINE_DEPENDENCIES=false ;;
      --cuda-architectures=*) CUDA_ARCHITECTURES="${argument#*=}" ;;
      --cpu-profile=*) CPU_PROFILE="${argument#*=}" ;;
      --source-dir=*) SOURCE_DIR="${argument#*=}" ;;
      --build-dir=*) BUILD_DIR="${argument#*=}" ;;
      --install-dir=*) INSTALL_DIR="${argument#*=}" ;;
      --clean-build) CLEAN_BUILD=true ;;
      --install-build-tools) INSTALL_BUILD_TOOLS=true ;;
      --no-install-build-tools) INSTALL_BUILD_TOOLS=false ;;
      --*) invalid "Unsupported option: ${argument}" ;;
      *) invalid "Unexpected argument: ${argument}" ;;
    esac
  done
}

validate.repository.url() {
  local value="$1" label="$2"
  [[ "${value}" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._+~-]+)+[.]git$ ]] ||
    invalid "${label} must be a credential-free HTTPS Git URL ending in .git."
  [[ "${value}" != *"@"* && "${value}" != *"?"* && "${value}" != *"#"* ]] ||
    invalid "${label} may not contain credentials, queries, or fragments."
}

validate.path.override() {
  local value="$1" prefix="$2" label="$3"
  [[ -z "${value}" ]] && return 0
  [[ "${value}" == "${prefix}/"* && "${value}" =~ ^/[A-Za-z0-9._/+~-]+$ && "${value}" != *".."* ]] ||
    invalid "${label} must be an absolute child of ${prefix}."
}

validate.configuration() {
  case "${FEATURE_MODE}" in preflight|apply|validate|upgrade) ;; *) invalid "Unsupported mode: ${FEATURE_MODE}" ;; esac
  for value in "${MATRIX_PROFILE}" "${RELEASE}" "${CPU_PROFILE}"; do
    [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Profile and release tokens contain unsupported characters."
  done
  [[ "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || invalid "--commit must be a lowercase full 40-character SHA."
  [[ "${SGLANG_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || invalid "--sglang-commit must be a lowercase full 40-character SHA."
  validate.repository.url "${REPOSITORY_URL}" "--repository-url"
  validate.repository.url "${SGLANG_REPOSITORY_URL}" "--sglang-repository-url"
  [[ "${INSTALL_PROFILE}" == source ]] || invalid "Only the reviewed source install profile is implemented."
  [[ "${PYTHON_VERSION}" =~ ^3[.]12[.][0-9]+$ ]] || invalid "The initial toolchain requires an exact Python 3.12 patch."
  [[ "${CUDA_ARCHITECTURES}" =~ ^[0-9]+([,;][0-9]+)*$ ]] || invalid "Invalid CUDA architecture list."
  validate.path.override "${SOURCE_DIR}" /opt/src/ktransformers --source-dir
  validate.path.override "${BUILD_DIR}" /opt/build/ktransformers --build-dir
  validate.path.override "${INSTALL_DIR}" /opt/venvs --install-dir
  if [[ -n "${WHEELHOUSE}" ]]; then
    [[ "${WHEELHOUSE}" =~ ^/[A-Za-z0-9._/+~-]+$ && "${WHEELHOUSE}" != *".."* ]] ||
      invalid "--wheelhouse must be a canonical absolute path."
  fi
  if [[ ("${FEATURE_MODE}" == apply || "${FEATURE_MODE}" == upgrade) && -z "${WHEELHOUSE}" && "${ALLOW_ONLINE_DEPENDENCIES}" != true ]]; then
    invalid "apply/upgrade requires --wheelhouse or explicit --allow-online-dependencies."
  fi
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  EXTRA_VARS_PATH="${TMP_DIR}/cli.llm.ktransformers.extra-vars.yml"
  PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
  COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
  SOURCE_PROFILE_HELPER_PATH="${PLAYBOOK_ROOT}/files/llm/source-profile.py"
  SOURCE_MATRIX_PATH="${PLAYBOOK_ROOT}/files/llm/ktransformers/compatibility-matrix.yml"
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
        runner.create.runtime llm-ktransformers "${RUNNER_TMP_PARENT}"
        configure.runtime.paths
        return
      fi
      ;;
  esac
  command -v wget >/dev/null 2>&1 || { log.error "wget is required."; exit "${EXIT_BLOCKED}"; }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-llm-ktransformers.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  log "Fetching shared runner helper: ${RUNNER_HELPER_URL}"
  wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" && [[ -s "${RUNNER_HELPER_PATH}" ]] ||
    { log.error "Failed to fetch ${RUNNER_HELPER_URL}"; exit "${EXIT_BLOCKED}"; }
  bash -n "${RUNNER_HELPER_PATH}" || { log.error "Downloaded runner helper is invalid."; exit "${EXIT_BLOCKED}"; }
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime llm-ktransformers "${bootstrap_dir}"
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
    { log.error "Unable to stage the KTransformers feature."; exit "${EXIT_BLOCKED}"; }
  PACKAGE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[0]}"
  FEATURE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

validate.reviewed.source() {
  PROFILE_JSON="$(
    python3 "${SOURCE_PROFILE_HELPER_PATH}" \
      --matrix "${SOURCE_MATRIX_PATH}" \
      --feature ktransformers \
      --profile "${MATRIX_PROFILE}" \
      --repository-url "${REPOSITORY_URL}" \
      --release "${RELEASE}" \
      --commit "${COMMIT}" \
      --sglang-repository-url "${SGLANG_REPOSITORY_URL}" \
      --sglang-commit "${SGLANG_COMMIT}"
  )" || { log.error "The requested KTransformers source tuple is not reviewed."; exit "${EXIT_BLOCKED}"; }
  local matrix_python_version=""
  matrix_python_version="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["python_version"])' "${PROFILE_JSON}")"
  [[ "${matrix_python_version}" == "${PYTHON_VERSION}" ]] ||
    { log.error "Python ${PYTHON_VERSION} is not approved by ${MATRIX_PROFILE}."; exit "${EXIT_BLOCKED}"; }
}

stage.reviewed.sources() {
  local resolved="" submodule_head="" submodule_remote="" python_url="" python_sha="" actual_sha=""
  command -v git >/dev/null 2>&1 || { log.error "git is required to stage reviewed source."; exit "${EXIT_BLOCKED}"; }
  STAGED_SOURCE_PATH="${TMP_DIR}/upstream/ktransformers"
  mkdir -p "$(dirname "${STAGED_SOURCE_PATH}")"
  git init -q "${STAGED_SOURCE_PATH}"
  git -C "${STAGED_SOURCE_PATH}" remote add origin "${REPOSITORY_URL}"
  log "Fetching reviewed KTransformers tag ${RELEASE} as the invoking user."
  git -C "${STAGED_SOURCE_PATH}" fetch -q --depth=1 origin "refs/tags/${RELEASE}:refs/tags/${RELEASE}"
  resolved="$(git -C "${STAGED_SOURCE_PATH}" rev-list -n 1 "refs/tags/${RELEASE}")"
  [[ "${resolved}" == "${COMMIT}" ]] ||
    { log.error "Tag ${RELEASE} resolves to ${resolved}, not ${COMMIT}."; exit "${EXIT_BLOCKED}"; }
  git -C "${STAGED_SOURCE_PATH}" -c advice.detachedHead=false checkout -q --detach "${COMMIT}"
  git -C "${STAGED_SOURCE_PATH}" submodule sync --recursive
  git -C "${STAGED_SOURCE_PATH}" submodule update --init --recursive
  submodule_head="$(git -C "${STAGED_SOURCE_PATH}/third_party/sglang" rev-parse HEAD)"
  submodule_remote="$(git -C "${STAGED_SOURCE_PATH}/third_party/sglang" remote get-url origin)"
  [[ "${submodule_head}" == "${SGLANG_COMMIT}" ]] ||
    { log.error "SGLang submodule is ${submodule_head}, not ${SGLANG_COMMIT}."; exit "${EXIT_BLOCKED}"; }
  [[ "${submodule_remote%.git}" == "${SGLANG_REPOSITORY_URL%.git}" ]] ||
    { log.error "SGLang submodule remote ${submodule_remote} is not approved."; exit "${EXIT_BLOCKED}"; }
  [[ -z "$(git -C "${STAGED_SOURCE_PATH}" status --porcelain)" ]] ||
    { log.error "Staged KTransformers source is unexpectedly dirty."; exit "${EXIT_BLOCKED}"; }

  python_url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["python_source_url"])' "${PROFILE_JSON}")"
  python_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["python_source_sha256"])' "${PROFILE_JSON}")"
  STAGED_PYTHON_ARCHIVE="${TMP_DIR}/upstream/Python-${PYTHON_VERSION}.tar.xz"
  log "Fetching and verifying the reviewed Python ${PYTHON_VERSION} source archive as the invoking user."
  wget -qO "${STAGED_PYTHON_ARCHIVE}" "${python_url}"
  actual_sha="$(sha256sum "${STAGED_PYTHON_ARCHIVE}" | awk '{print $1}')"
  [[ "${actual_sha}" == "${python_sha}" ]] ||
    { log.error "Python source SHA-256 ${actual_sha} does not match ${python_sha}."; exit "${EXIT_BLOCKED}"; }
}

write.extra.vars.file() {
  cat > "${EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_catalog_url: "${PAGES_BASE_URL}/ansible/packages.yml"
package_catalog_filename: "packages.yml"
package_group_allowlist: ["ktransformers_build"]
package_group_overrides:
  ktransformers_build: true
ktransformers_mode: "${FEATURE_MODE}"
ktransformers_matrix_profile: "${MATRIX_PROFILE}"
ktransformers_repository_url: "${REPOSITORY_URL}"
ktransformers_release: "${RELEASE}"
ktransformers_commit: "${COMMIT}"
ktransformers_sglang_repository_url: "${SGLANG_REPOSITORY_URL}"
ktransformers_sglang_commit: "${SGLANG_COMMIT}"
ktransformers_install_profile: "${INSTALL_PROFILE}"
ktransformers_python_version: "${PYTHON_VERSION}"
ktransformers_wheelhouse: "${WHEELHOUSE}"
ktransformers_allow_online_dependencies: ${ALLOW_ONLINE_DEPENDENCIES}
ktransformers_cuda_architectures: "${CUDA_ARCHITECTURES}"
ktransformers_cpu_profile: "${CPU_PROFILE}"
ktransformers_source_dir_override: "${SOURCE_DIR}"
ktransformers_build_dir_override: "${BUILD_DIR}"
ktransformers_install_dir_override: "${INSTALL_DIR}"
ktransformers_clean_build: ${CLEAN_BUILD}
ktransformers_install_build_tools: ${INSTALL_BUILD_TOOLS}
ktransformers_staged_source_path: "${STAGED_SOURCE_PATH}"
ktransformers_staged_python_archive: "${STAGED_PYTHON_ARCHIVE}"
EOF_VARS
}

run.preflight() {
  : > "${PREFLIGHT_REPORT_PATH}"
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "LLM host facts" /etc/ansible/debian/facts/llm-host.yml
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "NVIDIA facts" /etc/ansible/debian/facts/nvidia.yml
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Reviewed KTransformers tag" \
    git ls-remote --tags "${REPOSITORY_URL}" "refs/tags/${RELEASE}" "refs/tags/${RELEASE}^{}"
  printf '\n## Reviewed source policy\nprofile=%s\nrepository=%s\nrelease=%s\ncommit=%s\nsglang_repository=%s\nsglang_commit=%s\n' \
    "${MATRIX_PROFILE}" "${REPOSITORY_URL}" "${RELEASE}" "${COMMIT}" \
    "${SGLANG_REPOSITORY_URL}" "${SGLANG_COMMIT}" | tee -a "${PREFLIGHT_REPORT_PATH}"
  log "Preflight is read-only: no source/archive was downloaded, package installed, runtime created, model read, or fact written."
}

run.managed() {
  if [[ "${FEATURE_MODE}" == apply || "${FEATURE_MODE}" == upgrade ]]; then
    stage.reviewed.sources
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
