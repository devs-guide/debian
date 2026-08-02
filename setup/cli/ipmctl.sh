#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/ipmctl.sh
# Pinned Debian 13 source installer and read-only Intel Optane PMem verifier.

set -euo pipefail

readonly EXIT_SOFTWARE=1
readonly EXIT_HARDWARE=2
readonly EXIT_BLOCKED=3
readonly EXIT_USAGE=64
readonly IPMCTL_BIN=/usr/local/bin/ipmctl
readonly IPMCTL_VERSION=03.00.00.0538
readonly RUNNER_NAMESPACE=ansible

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
RUNNER_HELPER_PATH=""
COMMON_HELPER_PATH=""
RUNNER_LOCAL_REPO_ROOT=""
BUILD_USER=""
BUILD_HOME=""
BUILD_GROUP=""
FEATURE_MODE="${DEBIAN_IPMCTL_MODE:-install}"
SHOW_HELP=0

GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("install.packages.yml" "cli/ipmctl.yml")
RUNTIME_SUPPORT_REFS=(
  "packages.yml"
  "files/ipmctl/apply-patch.yml"
  "files/ipmctl/patches/README.md"
  "files/ipmctl/patches/0001-edk2-stable202511-host-os-build.patch"
  "files/ipmctl/patches/0002-ipmctl-disable-c-release-werror.patch"
  "files/ipmctl/patches/0003-ipmctl-remove-pie-from-shared-linker-flags.patch"
)
FEATURE_TEMPLATE_REFS=()
declare -a FEATURE_GROUP_VARS_ARGS=()
declare -a FEATURE_PLAYBOOK_PATHS=()

usage() {
  cat <<'EOF_USAGE'
Usage: ipmctl.sh [install|verify]

Modes:
  install  Build and install the reviewed Debian 13 source tuple, then verify.
  verify   Run software checks and four read-only PMem probes.

The runner supports Debian 13 amd64 only. It never creates or deletes a PMem
goal, changes firmware or security state, formats a DIMM, manages namespaces,
or schedules a reboot. The installed ipmctl binary itself remains a powerful
administrative tool; destructive commands are manual and outside this runner.
EOF_USAGE
}

parse.arguments() {
  (($# <= 1)) || invalid "Only one mode is accepted."
  case "${1:-${FEATURE_MODE}}" in
    install|verify) FEATURE_MODE="${1:-${FEATURE_MODE}}" ;;
    --help|-h) SHOW_HELP=1 ;;
    --*) invalid "Unsupported option: ${1}" ;;
    *) invalid "Unsupported mode: ${1}" ;;
  esac
}

require.platform() {
  local platform_id="" platform_version="" architecture=""
  [[ -r /etc/os-release ]] || { log.error "Debian os-release metadata is unavailable."; return "${EXIT_BLOCKED}"; }
  # shellcheck disable=SC1091
  source /etc/os-release
  platform_id="${ID:-}"
  platform_version="${VERSION_ID:-}"
  architecture="$(dpkg --print-architecture 2>/dev/null || true)"
  [[ "${platform_id}" == debian && "${platform_version}" == 13 && "${architecture}" == amd64 ]] || {
    log.error "Supported platform is Debian 13 amd64; found ${platform_id:-unknown} ${platform_version:-unknown} ${architecture:-unknown}."
    return "${EXIT_BLOCKED}"
  }
}

configure.runtime.paths() {
  TMP_DIR="${RUNNER_RUNTIME_DIR}"
  PLAYBOOK_ROOT="${TMP_DIR}/runtime"
  EXTRA_VARS_PATH="${TMP_DIR}/cli.ipmctl.extra-vars.yml"
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
        runner.create.runtime ipmctl "${RUNNER_TMP_PARENT}" "${RUNNER_NAMESPACE}"
        configure.runtime.paths
        return
      fi
      ;;
  esac

  command -v wget >/dev/null 2>&1 || { log.error "wget is required."; exit "${EXIT_BLOCKED}"; }
  bootstrap_dir="$(mktemp -d "${RUNNER_TMP_PARENT%/}/${RUNNER_NAMESPACE}-ipmctl.XXXXXX")"
  chmod 0700 "${bootstrap_dir}"
  RUNNER_HELPER_PATH="${bootstrap_dir}/${RUNNER_HELPER_NAME}"
  if ! wget -qO "${RUNNER_HELPER_PATH}" "${RUNNER_HELPER_URL}" || [[ ! -s "${RUNNER_HELPER_PATH}" ]]; then
    log.error "Failed to fetch ${RUNNER_HELPER_URL}."
    exit "${EXIT_BLOCKED}"
  fi
  bash -n "${RUNNER_HELPER_PATH}" || { log.error "Downloaded runner helper is invalid."; exit "${EXIT_BLOCKED}"; }
  # shellcheck disable=SC1090
  source "${RUNNER_HELPER_PATH}"
  runner.adopt.runtime ipmctl "${bootstrap_dir}" "${RUNNER_NAMESPACE}"
  configure.runtime.paths
}

source.release.common() {
  local local_setup_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_setup_root="${RUNNER_LOCAL_REPO_ROOT}/setup"
  runner.source.release.common "${local_setup_root}" "${PAGES_BASE_URL}/setup" "${TMP_DIR}" "${COMMON_HELPER_NAME}" || {
    log.error "Unable to stage the shared release helper."
    exit "${EXIT_BLOCKED}"
  }
}

prepare.feature.files() {
  local local_ansible_root=""
  [[ -z "${RUNNER_LOCAL_REPO_ROOT}" ]] || local_ansible_root="${RUNNER_LOCAL_REPO_ROOT}/ansible"
  runner.prepare.ansible.feature "${local_ansible_root}" "${PAGES_BASE_URL}/ansible" "${PLAYBOOK_ROOT}" || {
    log.error "Unable to stage the ipmctl feature."
    exit "${EXIT_BLOCKED}"
  }
  PACKAGE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[0]}"
  FEATURE_PLAYBOOK_PATH="${FEATURE_PLAYBOOK_PATHS[1]}"
}

resolve.build.identity() {
  local passwd_record=""
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    BUILD_USER="${SUDO_USER:-}"
    [[ -n "${BUILD_USER}" && "${BUILD_USER}" != root ]] || {
      log.error "Run install as a non-root user with sudo access; a direct root invocation is not accepted."
      return "${EXIT_BLOCKED}"
    }
  else
    BUILD_USER="$(id -un)"
  fi
  BUILD_GROUP="$(id -gn "${BUILD_USER}" 2>/dev/null || true)"
  passwd_record="$(getent passwd "${BUILD_USER}" 2>/dev/null || true)"
  BUILD_HOME="$(printf '%s\n' "${passwd_record}" | cut -d: -f6)"
  [[ "${BUILD_USER}" =~ ^[a-z_][a-z0-9_-]*[$]?$ && "${BUILD_GROUP}" =~ ^[a-z_][a-z0-9_-]*[$]?$ && "${BUILD_HOME}" == /* && -d "${BUILD_HOME}" ]] || {
    log.error "Unable to resolve a safe build user and home directory."
    return "${EXIT_BLOCKED}"
  }
}

write.extra.vars.file() {
  cat >"${EXTRA_VARS_PATH}" <<EOF_VARS
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_catalog_url: "${PAGES_BASE_URL}/ansible/packages.yml"
package_catalog_filename: "packages.yml"
package_group_allowlist: ["ipmctl_build"]
package_group_overrides:
  ipmctl_build: true
ipmctl_mode: "install"
ipmctl_build_user: "${BUILD_USER}"
ipmctl_build_group: "${BUILD_GROUP}"
ipmctl_build_home: "${BUILD_HOME}"
EOF_VARS
  chmod 0600 "${EXTRA_VARS_PATH}"
}

software.verify() {
  local version_output="" version_token="" linkage_output=""
  [[ -x "${IPMCTL_BIN}" ]] || { log.error "Reviewed binary is unavailable: ${IPMCTL_BIN}"; return "${EXIT_SOFTWARE}"; }
  if ! version_output="$(${IPMCTL_BIN} version 2>&1)"; then
    log.error "ipmctl version failed: ${version_output}"
    return "${EXIT_SOFTWARE}"
  fi
  version_token="$(printf '%s\n' "${version_output}" | grep -Eo '[0-9]{2}[.][0-9]{2}[.][0-9]{2}[.][0-9]{4}' | head -n1 || true)"
  [[ "${version_token}" == "${IPMCTL_VERSION}" ]] || {
    log.error "Expected ipmctl ${IPMCTL_VERSION}; observed ${version_token:-unknown}."
    return "${EXIT_SOFTWARE}"
  }
  if ! linkage_output="$(ldd "${IPMCTL_BIN}" 2>&1)"; then
    log.error "Unable to inspect ipmctl runtime linkage: ${linkage_output}"
    return "${EXIT_SOFTWARE}"
  fi
  [[ "${linkage_output}" != *"not found"* ]] || {
    log.error "ipmctl has unresolved runtime linkage."
    printf '%s\n' "${linkage_output}" >&2
    return "${EXIT_SOFTWARE}"
  }
  printf '[PASS] software  version=%s binary=%s\n' "${version_token}" "${IPMCTL_BIN}"
  printf '%s\n' "${linkage_output}"
}

hardware.probe() {
  local id="$1" label="$2" output_path="" error_path="" status=0
  shift 2
  output_path="${RUNNER_RUNTIME_DIR}/${id}.stdout"
  error_path="${RUNNER_RUNTIME_DIR}/${id}.stderr"
  if runner.run.as.root "${IPMCTL_BIN}" "$@" >"${output_path}" 2>"${error_path}"; then
    status=0
  else
    status=$?
  fi
  printf '\n## %s\n' "${label}"
  [[ ! -s "${output_path}" ]] || sed -n '1,320p' "${output_path}"
  [[ ! -s "${error_path}" ]] || sed -n '1,160p' "${error_path}" >&2
  if [[ "${status}" -eq 0 ]]; then
    if [[ ! -s "${output_path}" ]]; then
      printf '[WARN] %s returned no output\n' "${label}" >&2
      return 1
    fi
    printf '[PASS] %s\n' "${label}"
  else
    printf '[WARN] %s (exit=%s)\n' "${label}" "${status}" >&2
  fi
  return "${status}"
}

run.verify() {
  local hardware_warning=0
  local dimms_result=WARN topology_result=WARN memoryresources_result=WARN goal_result=WARN
  software.verify || return "${EXIT_SOFTWARE}"
  runner.ensure.privileged.session || return "${EXIT_BLOCKED}"
  if hardware.probe dimms "PMem DIMMs" show -a -dimm; then dimms_result=PASS; else hardware_warning=1; fi
  if hardware.probe topology "PMem topology" show -topology; then topology_result=PASS; else hardware_warning=1; fi
  if hardware.probe memoryresources "PMem memory resources" show -memoryresources; then memoryresources_result=PASS; else hardware_warning=1; fi
  if hardware.probe goal "PMem current or pending goal" show -a -goal; then goal_result=PASS; else hardware_warning=1; fi
  printf '\n%-24s | %-6s | %s\n' Probe Result Meaning
  printf '%-24s-+-%-6s-+-%s\n' '------------------------' '------' '---------------------------------------------'
  printf '%-24s | %-6s | %s\n' 'version/linkage' PASS 'CLI installation health'
  printf '%-24s | %-6s | %s\n' DIMMs "${dimms_result}" 'module discovery'
  printf '%-24s | %-6s | %s\n' topology "${topology_result}" 'platform topology/PMTT visibility'
  printf '%-24s | %-6s | %s\n' 'memory resources' "${memoryresources_result}" 'current volatile/App Direct allocation'
  printf '%-24s | %-6s | %s\n' 'current/pending goal' "${goal_result}" 'read-only goal report'
  if [[ "${hardware_warning}" -ne 0 ]]; then
    log "Software is installed, but one or more hardware probes require human review."
    return "${EXIT_HARDWARE}"
  fi
  log "Software and all read-only hardware probes passed."
}

run.install() {
  resolve.build.identity
  source.release.common
  prepare.feature.files
  runner.ensure.privileged.session || return "${EXIT_BLOCKED}"
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || runner.ensure.local.ansible
  write.extra.vars.file
  log "Installing the reviewed ipmctl build dependency group."
  runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${PACKAGE_PLAYBOOK_PATH}"
  log "Building and installing the pinned ipmctl source tuple."
  runner.run.ansible.playbooks "${EXTRA_VARS_PATH}" "${FEATURE_PLAYBOOK_PATH}"
  run.verify
}

main() {
  parse.arguments "$@"
  [[ "${SHOW_HELP}" -eq 0 ]] || { usage; return 0; }
  require.platform
  source.runner.common
  if [[ "${FEATURE_MODE}" == install ]]; then
    run.install
  else
    run.verify
  fi
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
