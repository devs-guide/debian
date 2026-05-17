#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/hardware.sh
## Manual Debian hardware setup runner.
## Local usage:
##   ./setup/hardware.sh [preflight|apply]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/hardware | bash

set -euo pipefail

log() { printf '[setup.hardware] %s\n' "$*" >&2; }
log.error() { printf '[setup.hardware][error] %s\n' "$*" >&2; }

TMP_ROOT_DIR="${TMP_ROOT_DIR:-/tmp/ansible/debian}"
TMP_DIR="${TMP_DIR:-${TMP_ROOT_DIR}/hardware}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
PLAYBOOK_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
LOCAL_COMMON_HELPER="../release.common.sh"
COMMON_HELPER_NAME="release.common.sh"
COMMON_HELPER_URL="${PAGES_BASE_URL}/setup/${COMMON_HELPER_NAME}"
COMMON_HELPER_PATH="${TMP_DIR}/${COMMON_HELPER_NAME}"
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=(
  "install.packages.yml"
  "performance.yml"
  "power.yml"
)
RUNTIME_SUPPORT_REFS=("packages.yml")
INSTALL_PACKAGES_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[0]}"
PERFORMANCE_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[1]}"
POWER_PLAYBOOK_REL="${FEATURE_PLAYBOOKS[2]}"
INSTALL_PACKAGES_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${INSTALL_PACKAGES_PLAYBOOK_REL}"
PERFORMANCE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${PERFORMANCE_PLAYBOOK_REL}"
POWER_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${POWER_PLAYBOOK_REL}"
HARDWARE_EXTRA_VARS_PATH="${TMP_DIR}/hardware.extra-vars.yml"
FEATURE_MODE="${1:-${DEBIAN_HARDWARE_MODE:-apply}}"
DEBIAN_HARDWARE_ARCHIVE_TOOLS="${DEBIAN_HARDWARE_ARCHIVE_TOOLS:-0}"
DEBIAN_HARDWARE_FIRMWARE="${DEBIAN_HARDWARE_FIRMWARE:-0}"
DEBIAN_HARDWARE_DEV_TOOLS="${DEBIAN_HARDWARE_DEV_TOOLS:-0}"
DEBIAN_HARDWARE_APPLY_PERFORMANCE="${DEBIAN_HARDWARE_APPLY_PERFORMANCE:-0}"
DEBIAN_HARDWARE_CPUPOWER_ENABLE="${DEBIAN_HARDWARE_CPUPOWER_ENABLE:-0}"
DEBIAN_HARDWARE_USB_AUTOSUSPEND_DISABLE="${DEBIAN_HARDWARE_USB_AUTOSUSPEND_DISABLE:-0}"
DEBIAN_HARDWARE_DISABLE_CONSOLE_BLANKING="${DEBIAN_HARDWARE_DISABLE_CONSOLE_BLANKING:-0}"
DEBIAN_HARDWARE_POWER_POLICY="${DEBIAN_HARDWARE_POWER_POLICY:-0}"
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
  # shellcheck source=/tmp/ansible/debian/hardware/release.common.sh
  source "${COMMON_HELPER_PATH}"
}

is.true() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
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

use.local.feature.files() {
  local script_dir repo_root file

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"

  for file in "${GROUP_VARS_FILES[@]}"; do
    if [[ ! -r "${repo_root}/ansible/group_vars/${file}" ]]; then
      return 1
    fi
  done

  if [[ -r "${repo_root}/ansible/${INSTALL_PACKAGES_PLAYBOOK_REL}" && -r "${repo_root}/ansible/${PERFORMANCE_PLAYBOOK_REL}" && -r "${repo_root}/ansible/${POWER_PLAYBOOK_REL}" ]]; then
    PLAYBOOK_ROOT="${repo_root}/ansible"
    PLAYBOOK_GROUP_VARS_DIR="${PLAYBOOK_ROOT}/group_vars"
    INSTALL_PACKAGES_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${INSTALL_PACKAGES_PLAYBOOK_REL}"
    PERFORMANCE_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${PERFORMANCE_PLAYBOOK_REL}"
    POWER_PLAYBOOK_PATH="${PLAYBOOK_ROOT}/${POWER_PLAYBOOK_REL}"
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

  fetch.feature.file "${PAGES_BASE_URL}/ansible/${INSTALL_PACKAGES_PLAYBOOK_REL}" "${INSTALL_PACKAGES_PLAYBOOK_PATH}"
  fetch.feature.file "${PAGES_BASE_URL}/ansible/${PERFORMANCE_PLAYBOOK_REL}" "${PERFORMANCE_PLAYBOOK_PATH}"
  fetch.feature.file "${PAGES_BASE_URL}/ansible/${POWER_PLAYBOOK_REL}" "${POWER_PLAYBOOK_PATH}"
  fetch.feature.file "${PAGES_BASE_URL}/ansible/packages.yml" "${PLAYBOOK_ROOT}/packages.yml"
  reset.feature.extra.vars.args
}

run.feature.playbook() {
  local playbook_path="$1"
  shift
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${FEATURE_GROUP_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

write.hardware.extra.vars.file() {
  local archive_iso_tools=false
  local firmware=false
  local dev_tools=false
  local cpupower_enable=false
  local usb_autosuspend_disable=false
  local disable_console_blanking=false

  if is.true "${DEBIAN_HARDWARE_ARCHIVE_TOOLS}"; then archive_iso_tools=true; fi
  if is.true "${DEBIAN_HARDWARE_FIRMWARE}"; then firmware=true; fi
  if is.true "${DEBIAN_HARDWARE_DEV_TOOLS}"; then dev_tools=true; fi
  if is.true "${DEBIAN_HARDWARE_CPUPOWER_ENABLE}"; then cpupower_enable=true; fi
  if is.true "${DEBIAN_HARDWARE_USB_AUTOSUSPEND_DISABLE}"; then usb_autosuspend_disable=true; fi
  if is.true "${DEBIAN_HARDWARE_DISABLE_CONSOLE_BLANKING}"; then disable_console_blanking=true; fi

  mkdir -p "${TMP_DIR}"
  cat > "${HARDWARE_EXTRA_VARS_PATH}" <<EOF
---
ansible_python_interpreter_managed: "/usr/bin/python3"
package_feature_profile: "hardware"
package_show_disabled_groups: false
package_group_allowlist:
  - base
  - storage
  - hardware_info
  - monitoring_benchmark
  - performance_power
  - archive_iso_tools
  - firmware
  - dev_tools
exclude_packages:
  - radeontop
  - intel-gpu-tools
  - nvidia-detect
  - firmware-amd-graphics
package_group_overrides:
  base: true
  storage: true
  hardware_info: true
  monitoring_benchmark: true
  performance_power: true
  archive_iso_tools: ${archive_iso_tools}
  firmware: ${firmware}
  dev_tools: ${dev_tools}
  desktop_rdp_optional: false
  apple_media_optional: false
  gpu_vendor_optional: false
  security: false
  networking: false
  time_sync: false
cpupower_enable: ${cpupower_enable}
usb_autosuspend_disable: ${usb_autosuspend_disable}
disable_console_blanking: ${disable_console_blanking}
EOF
  log "Prepared hardware extra-vars: ${HARDWARE_EXTRA_VARS_PATH}"
}

run.preflight() {
  log "Feature mode: ${FEATURE_MODE}"
  log "Package groups default: base, storage, hardware_info, monitoring_benchmark, performance_power"
  log "GPU packages are intentionally excluded; use future setup/gpu for GPU drivers, passthrough, and telemetry"
  log "Package groups optional: archive_iso_tools=${DEBIAN_HARDWARE_ARCHIVE_TOOLS}, firmware=${DEBIAN_HARDWARE_FIRMWARE}, dev_tools=${DEBIAN_HARDWARE_DEV_TOOLS}"
  log "Optional playbooks: performance.yml=${DEBIAN_HARDWARE_APPLY_PERFORMANCE}, power.yml=${DEBIAN_HARDWARE_POWER_POLICY}"

  uname -a || true
  lscpu || true
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL || true
  lspci -nn || true
  lsusb || true
  ip -br link || true
  sensors || true
  command -v smartctl >/dev/null 2>&1 && smartctl --scan || true
  command -v nvme >/dev/null 2>&1 && nvme list || true

  log "Apply command:"
  log "  wget -qO- ${PAGES_BASE_URL}/setup/hardware | bash"
}

run.hardware.feature() {
  write.hardware.extra.vars.file

  log "Running package installation playbook..."
  run.feature.playbook "${INSTALL_PACKAGES_PLAYBOOK_PATH}" -e "@${HARDWARE_EXTRA_VARS_PATH}"

  if is.true "${DEBIAN_HARDWARE_APPLY_PERFORMANCE}"; then
    log "Running optional performance playbook..."
    run.feature.playbook "${PERFORMANCE_PLAYBOOK_PATH}" -e "@${HARDWARE_EXTRA_VARS_PATH}"
  else
    log "Skipping performance.yml (set DEBIAN_HARDWARE_APPLY_PERFORMANCE=1 to enable)"
  fi

  if is.true "${DEBIAN_HARDWARE_POWER_POLICY}"; then
    log "Running optional power playbook..."
    run.feature.playbook "${POWER_PLAYBOOK_PATH}" -e "@${HARDWARE_EXTRA_VARS_PATH}"
  else
    log "Skipping power.yml (set DEBIAN_HARDWARE_POWER_POLICY=1 to enable)"
  fi
}

main() {
  reset.feature.tmp.cache
  source.release.common
  require.root
  require.apt
  require.debian.host
  require.valid.mode

  if [[ "${FEATURE_MODE}" == "preflight" ]]; then
    run.preflight
    exit 0
  fi

  ensure.local.ansible
  prepare.feature.files
  run.hardware.feature
}

main "$@"
