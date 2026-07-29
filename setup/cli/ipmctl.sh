#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/ipmctl.sh
# Pinned Intel Optane PMem inventory, source build, and guarded goal runner.
#
# wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
#   bash -s -- preflight --profile=trixie-v03.00.00.0538

set -euo pipefail

readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64
readonly GOAL_CONFIRMATION="I UNDERSTAND PMEM GOAL CHANGES DESTROY DATA AND REQUIRE REBOOT"

log() { printf '[setup.cli.ipmctl] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.ipmctl][error] %s\n' "$*" >&2; }
invalid() { log.error "$*"; exit "${EXIT_USAGE}"; }

RUNNER_TMP_PARENT="${DEBIAN_RUNNER_TMP_PARENT:-/tmp}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
LOCAL_RUNNER_HELPER="../runner.common.sh"
RUNNER_HELPER_NAME="runner.common.sh"
RUNNER_HELPER_URL="${PAGES_BASE_URL}/setup/${RUNNER_HELPER_NAME}"
COMMON_HELPER_NAME="release.common.sh"

TMP_DIR=""
PLAYBOOK_ROOT=""
PACKAGE_PLAYBOOK_PATH=""
FEATURE_PLAYBOOK_PATH=""
EXTRA_VARS_PATH=""
PREFLIGHT_REPORT_PATH=""
GOAL_PLAN_RESULT_PATH=""
SOURCE_PROFILE_HELPER_PATH=""
SOURCE_MATRIX_PATH=""
STAGED_IPMCTL_SOURCE=""
STAGED_EDK2_SOURCE=""
RUNNER_HELPER_PATH=""
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("install.packages.yml" "cli/ipmctl.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "files/ipmctl/source-profile.py"
  "files/ipmctl/ipmctl-inventory.py"
  "files/ipmctl/compatibility-matrix.yml"
)
FEATURE_TEMPLATE_REFS=()
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

FEATURE_MODE="${DEBIAN_IPMCTL_MODE:-preflight}"
PROFILE="${DEBIAN_IPMCTL_PROFILE:-trixie-v03.00.00.0538}"
REPOSITORY_URL="${DEBIAN_IPMCTL_REPOSITORY_URL:-https://github.com/intel/ipmctl.git}"
RELEASE="${DEBIAN_IPMCTL_RELEASE:-v03.00.00.0538}"
COMMIT="${DEBIAN_IPMCTL_COMMIT:-a71f2fb1c90dd07f9862b71c789881132193e8f9}"
EDK2_REPOSITORY_URL="${DEBIAN_IPMCTL_EDK2_REPOSITORY_URL:-https://github.com/tianocore/edk2.git}"
EDK2_RELEASE="${DEBIAN_IPMCTL_EDK2_RELEASE:-edk2-stable202405}"
EDK2_COMMIT="${DEBIAN_IPMCTL_EDK2_COMMIT:-3e722403cd16388a0e4044e705a2b34c841d76ca}"
BUILD_TYPE="${DEBIAN_IPMCTL_BUILD_TYPE:-release}"
INSTALL_BUILD_TOOLS="${DEBIAN_IPMCTL_INSTALL_BUILD_TOOLS:-false}"
GOAL="${DEBIAN_IPMCTL_GOAL:-}"
SOCKET_TARGET="${DEBIAN_IPMCTL_SOCKET:-}"
ALLOW_DESTRUCTIVE_GOAL_CHANGE="${DEBIAN_IPMCTL_ALLOW_DESTRUCTIVE_GOAL_CHANGE:-false}"
GOAL_CONFIRMATION_AUTHORIZED=false
SHOW_HELP=0

usage() {
  cat <<'EOF_USAGE'
Usage: ipmctl.sh [preflight|apply|validate|goal-plan|goal-apply] [options]

Modes:
  preflight                  Unprivileged read-only policy and host report.
  apply                      Build, install, inventory, and persist facts only.
  validate                   Refresh privileged read-only inventory and facts.
  goal-plan                  Print a privileged read-only PMem goal plan.
  goal-apply                 Re-plan, confirm exactly, and create one goal.

Options:
  --profile=trixie-v03.00.00.0538
  --repository-url=HTTPS_GIT_URL
  --release=TAG
  --commit=FULL_40_CHARACTER_SHA
  --edk2-repository-url=HTTPS_GIT_URL
  --edk2-release=TAG
  --edk2-commit=FULL_40_CHARACTER_SHA
  --build-type=release|debug
  --install-build-tools
  --no-install-build-tools
  --goal=memory-mode|app-direct|app-direct-not-interleaved
  --socket=all|COMMA_SEPARATED_SOCKET_IDS
  --allow-destructive-goal-change
  --help

Reviewed Debian 13 source install:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
    bash -s -- apply \
      --profile=trixie-v03.00.00.0538 \
      --repository-url=https://github.com/intel/ipmctl.git \
      --release=v03.00.00.0538 \
      --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
      --edk2-repository-url=https://github.com/tianocore/edk2.git \
      --edk2-release=edk2-stable202405 \
      --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
      --build-type=release \
      --install-build-tools

Destructive Memory Mode workflow:
  wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
    bash -s -- goal-plan \
      --profile=trixie-v03.00.00.0538 \
      --repository-url=https://github.com/intel/ipmctl.git \
      --release=v03.00.00.0538 \
      --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
      --edk2-repository-url=https://github.com/tianocore/edk2.git \
      --edk2-release=edk2-stable202405 \
      --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
      --build-type=release \
      --goal=memory-mode \
      --socket=all \
      --no-install-build-tools

  wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
    bash -s -- goal-apply \
      --profile=trixie-v03.00.00.0538 \
      --repository-url=https://github.com/intel/ipmctl.git \
      --release=v03.00.00.0538 \
      --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
      --edk2-repository-url=https://github.com/tianocore/edk2.git \
      --edk2-release=edk2-stable202405 \
      --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
      --build-type=release \
      --goal=memory-mode \
      --socket=all \
      --no-install-build-tools \
      --allow-destructive-goal-change

goal-apply can destroy App Direct data and requires a reboot. It never deletes
namespaces or PCD, changes firmware/security, or reboots. There is no
noninteractive confirmation bypass.
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
      --profile=*) PROFILE="${argument#*=}" ;;
      --repository-url=*) REPOSITORY_URL="${argument#*=}" ;;
      --release=*) RELEASE="${argument#*=}" ;;
      --commit=*) COMMIT="${argument#*=}" ;;
      --edk2-repository-url=*) EDK2_REPOSITORY_URL="${argument#*=}" ;;
      --edk2-release=*) EDK2_RELEASE="${argument#*=}" ;;
      --edk2-commit=*) EDK2_COMMIT="${argument#*=}" ;;
      --build-type=*) BUILD_TYPE="${argument#*=}" ;;
      --install-build-tools) INSTALL_BUILD_TOOLS=true ;;
      --no-install-build-tools) INSTALL_BUILD_TOOLS=false ;;
      --goal=*) GOAL="${argument#*=}" ;;
      --socket=*) SOCKET_TARGET="${argument#*=}" ;;
      --allow-destructive-goal-change) ALLOW_DESTRUCTIVE_GOAL_CHANGE=true ;;
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
    invalid "${label} cannot contain credentials, a query, or a fragment."
}

validate.configuration() {
  case "${FEATURE_MODE}" in preflight|apply|validate|goal-plan|goal-apply) ;; *) invalid "Unsupported mode: ${FEATURE_MODE}" ;; esac
  [[ "${PROFILE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid profile."
  [[ "${RELEASE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid release."
  [[ "${EDK2_RELEASE}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || invalid "Invalid edk2 release."
  [[ "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || invalid "--commit must be a lowercase full 40-character SHA."
  [[ "${EDK2_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || invalid "--edk2-commit must be a lowercase full 40-character SHA."
  validate.repository.url "${REPOSITORY_URL}" --repository-url
  validate.repository.url "${EDK2_REPOSITORY_URL}" --edk2-repository-url
  case "${BUILD_TYPE}" in release|debug) ;; *) invalid "--build-type must be release or debug." ;; esac
  case "${INSTALL_BUILD_TOOLS}" in true|false) ;; *) invalid "Invalid build-tool policy." ;; esac
  case "${ALLOW_DESTRUCTIVE_GOAL_CHANGE}" in true|false) ;; *) invalid "Invalid destructive-goal policy." ;; esac
  if [[ "${FEATURE_MODE}" == goal-plan || "${FEATURE_MODE}" == goal-apply ]]; then
    case "${GOAL}" in memory-mode|app-direct|app-direct-not-interleaved) ;; *) invalid "Goal modes require an explicit supported --goal." ;; esac
    [[ "${SOCKET_TARGET}" == all || "${SOCKET_TARGET}" =~ ^[0-9]+(,[0-9]+)*$ ]] ||
      invalid "Goal modes require --socket=all or a comma-separated socket list."
  elif [[ -n "${GOAL}" || -n "${SOCKET_TARGET}" || "${ALLOW_DESTRUCTIVE_GOAL_CHANGE}" == true ]]; then
    invalid "Goal options are accepted only by goal-plan or goal-apply."
  fi
  if [[ "${FEATURE_MODE}" == goal-apply && "${ALLOW_DESTRUCTIVE_GOAL_CHANGE}" != true ]]; then
    invalid "goal-apply requires --allow-destructive-goal-change."
  fi
  [[ "${FEATURE_MODE}" == apply || "${INSTALL_BUILD_TOOLS}" != true ]] ||
    invalid "--install-build-tools is accepted only by apply."
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  EXTRA_VARS_PATH="${TMP_DIR}/cli.ipmctl.extra-vars.yml"
  PREFLIGHT_REPORT_PATH="${TMP_DIR}/preflight.txt"
  GOAL_PLAN_RESULT_PATH="${TMP_DIR}/goal-plan.result"
  COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
  SOURCE_PROFILE_HELPER_PATH="${PLAYBOOK_ROOT}/files/ipmctl/source-profile.py"
  SOURCE_MATRIX_PATH="${PLAYBOOK_ROOT}/files/ipmctl/compatibility-matrix.yml"
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
        source "${RUNNER_HELPER_PATH}"
        runner.create.runtime ipmctl "${RUNNER_TMP_PARENT}"
        configure.runtime.paths
        return
      fi
      ;;
  esac
  command -v wget >/dev/null 2>&1 || { log.error "wget is required."; exit "${EXIT_BLOCKED}"; }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/devs-guide-ipmctl.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  log "Fetching shared runner helper: ${RUNNER_HELPER_URL}"
  wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" && [[ -s "${RUNNER_HELPER_PATH}" ]] ||
    { log.error "Failed to fetch ${RUNNER_HELPER_URL}"; exit "${EXIT_BLOCKED}"; }
  bash -n "${RUNNER_HELPER_PATH}" || { log.error "Downloaded runner helper is invalid."; exit "${EXIT_BLOCKED}"; }
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime ipmctl "${bootstrap_dir}"
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
    { log.error "Unable to stage the ipmctl feature."; exit "${EXIT_BLOCKED}"; }
  PACKAGE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[0]}"
  FEATURE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

validate.reviewed.source() {
  python3 "${SOURCE_PROFILE_HELPER_PATH}" \
    --matrix "${SOURCE_MATRIX_PATH}" \
    --profile "${PROFILE}" \
    --repository-url "${REPOSITORY_URL}" \
    --release "${RELEASE}" \
    --commit "${COMMIT}" \
    --edk2-repository-url "${EDK2_REPOSITORY_URL}" \
    --edk2-release "${EDK2_RELEASE}" \
    --edk2-commit "${EDK2_COMMIT}" >/dev/null ||
    { log.error "The requested ipmctl/edk2 source tuple is not reviewed."; exit "${EXIT_BLOCKED}"; }
}

stage.one.source() {
  local destination="$1" repository="$2" release="$3" commit="$4" label="$5" resolved=""
  git init -q "${destination}"
  git -C "${destination}" remote add origin "${repository}"
  log "Fetching reviewed ${label} tag ${release} as the invoking user."
  git -C "${destination}" fetch -q --depth=1 origin "refs/tags/${release}:refs/tags/${release}"
  resolved="$(git -C "${destination}" rev-list -n 1 "refs/tags/${release}")"
  [[ "${resolved}" == "${commit}" ]] ||
    { log.error "${label} tag ${release} resolves to ${resolved}, not ${commit}."; exit "${EXIT_BLOCKED}"; }
  git -C "${destination}" -c advice.detachedHead=false checkout -q --detach "${commit}"
  [[ -z "$(git -C "${destination}" status --porcelain)" ]] ||
    { log.error "Staged ${label} source is unexpectedly dirty."; exit "${EXIT_BLOCKED}"; }
}

stage.reviewed.sources() {
  command -v git >/dev/null 2>&1 || { log.error "git is required to stage reviewed source."; exit "${EXIT_BLOCKED}"; }
  STAGED_IPMCTL_SOURCE="${TMP_DIR}/upstream/ipmctl"
  STAGED_EDK2_SOURCE="${TMP_DIR}/upstream/edk2"
  mkdir -p "${TMP_DIR}/upstream"
  stage.one.source "${STAGED_IPMCTL_SOURCE}" "${REPOSITORY_URL}" "${RELEASE}" "${COMMIT}" ipmctl
  stage.one.source "${STAGED_EDK2_SOURCE}" "${EDK2_REPOSITORY_URL}" "${EDK2_RELEASE}" "${EDK2_COMMIT}" edk2
}

write.extra.vars.file() {
  cat > "${EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_catalog_url: "${PAGES_BASE_URL}/ansible/packages.yml"
package_catalog_filename: "packages.yml"
package_group_allowlist: ["ipmctl_build"]
package_group_overrides:
  ipmctl_build: true
ipmctl_mode: "${FEATURE_MODE}"
ipmctl_profile: "${PROFILE}"
ipmctl_repository_url: "${REPOSITORY_URL}"
ipmctl_release: "${RELEASE}"
ipmctl_commit: "${COMMIT}"
ipmctl_edk2_repository_url: "${EDK2_REPOSITORY_URL}"
ipmctl_edk2_release: "${EDK2_RELEASE}"
ipmctl_edk2_commit: "${EDK2_COMMIT}"
ipmctl_build_type: "${BUILD_TYPE}"
ipmctl_install_build_tools: ${INSTALL_BUILD_TOOLS}
ipmctl_staged_source_path: "${STAGED_IPMCTL_SOURCE}"
ipmctl_staged_edk2_path: "${STAGED_EDK2_SOURCE}"
ipmctl_goal: "${GOAL}"
ipmctl_socket_target: "${SOCKET_TARGET}"
ipmctl_goal_plan_result_path: "${GOAL_PLAN_RESULT_PATH}"
ipmctl_goal_confirmation_authorized: ${GOAL_CONFIRMATION_AUTHORIZED}
EOF_VARS
}

run.read.only.preflight() {
  : > "${PREFLIGHT_REPORT_PATH}"
  runner.report.text "${PREFLIGHT_REPORT_PATH}" "Managed ipmctl facts" /etc/ansible/debian/facts/ipmctl.yml
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Debian release" sed -n '1,20p' /etc/os-release
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Installed ipmctl binary" sh -c 'command -v ipmctl && ipmctl version'
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Debian ipmctl package policy" apt-cache policy ipmctl
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Intel Optane PMem modules" ipmctl show -a -dimm
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Intel Optane PMem topology" ipmctl show -topology
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Persistent-memory resources" ipmctl show -u B -memoryresources
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Persistent-memory regions" ipmctl show -a -region
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Persistent-memory capabilities" ipmctl show -a -system -capabilities
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Pending persistent-memory goal" ipmctl show -a -goal
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Linux persistent-memory devices" ndctl list -D
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Linux persistent-memory regions" ndctl list -R
  runner.report.command "${PREFLIGHT_REPORT_PATH}" "Linux persistent-memory namespaces" ndctl list -N
  printf '\n## Reviewed source policy\nprofile=%s\nipmctl=%s %s %s\nedk2=%s %s %s\nbuild_type=%s\n' \
    "${PROFILE}" "${REPOSITORY_URL}" "${RELEASE}" "${COMMIT}" \
    "${EDK2_REPOSITORY_URL}" "${EDK2_RELEASE}" "${EDK2_COMMIT}" "${BUILD_TYPE}" |
    tee -a "${PREFLIGHT_REPORT_PATH}"
  log "Preflight is read-only: no source was cloned, package installed, fact written, or PMem goal changed."
}

run.package.playbook() {
  runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${PACKAGE_PLAYBOOK_PATH}"
}

run.feature.playbook() {
  runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${FEATURE_PLAYBOOK_PATH}"
}

ensure.local.ansible.as.root() {
  runner.ensure.local.ansible
}

run.managed.mode() {
  runner.ensure.privileged.session || exit "${EXIT_BLOCKED}"
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || ensure.local.ansible.as.root
  if [[ "${FEATURE_MODE}" == apply && "${INSTALL_BUILD_TOOLS}" == true ]]; then
    write.extra.vars.file
    log "Installing the opt-in ipmctl source-build package group."
    run.package.playbook
  fi
  if [[ "${FEATURE_MODE}" == apply ]]; then
    stage.reviewed.sources
  fi
  if [[ "${FEATURE_MODE}" == goal-apply ]]; then
    FEATURE_MODE=goal-plan
    write.extra.vars.file
    run.feature.playbook
    if grep -Fxq 'no_op=true' "${GOAL_PLAN_RESULT_PATH}"; then
      log "Requested PMem mode is already active and settled; refreshing facts without confirmation or mutation."
      FEATURE_MODE=validate
      write.extra.vars.file
      run.feature.playbook
      return 0
    fi
    runner.confirm.exact \
      "The displayed ipmctl goal can destroy App Direct data and requires a BIOS reboot to apply. No namespace, PCD, firmware, security, or reboot operation will be performed automatically." \
      "${GOAL_CONFIRMATION}"
    GOAL_CONFIRMATION_AUTHORIZED=true
    FEATURE_MODE=goal-apply
  fi
  write.extra.vars.file
  run.feature.playbook
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
    run.read.only.preflight
  else
    run.managed.mode
  fi
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
