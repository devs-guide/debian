#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/release.common.sh

set -euo pipefail

: "${PYTHON_VERSION:=3.12.3}"
: "${PYTHON_MAJOR_MINOR:=3.12}"
: "${PYTHON_MIN_VERSION:=3.12.3}"
: "${PYTHON_SOURCE_PREFIX:=/usr/local}"
: "${PYTHON_BIN:=${PYTHON_SOURCE_PREFIX}/bin/python${PYTHON_MAJOR_MINOR}}"
: "${PYTHON_SRC_DIR:=${PYTHON_SOURCE_PREFIX}/src/Python-${PYTHON_VERSION}}"
: "${PYTHON_SRC_ARCHIVE:=${PYTHON_SRC_DIR}.tgz}"
: "${PYTHON_SRC_URL:=https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz}"

# Release-aware controller policy.
: "${CONTROLLER_PYTHON_POLICY:=auto}"
: "${CONTROLLER_PYTHON_PROVIDER:=auto}"
: "${SYSTEM_PYTHON_BIN:=/usr/bin/python3}"
: "${CONTROLLER_PYTHON_BIN:=}"
: "${CONTROLLER_PYTHON_VERSION:=}"
: "${CONTROLLER_PYTHON_NATIVE_MAJOR_MINOR:=}"
: "${CONTROLLER_PYTHON_NATIVE_VERSION_HINT:=}"
: "${CONTROLLER_PYTHON_REBUILD_FOR_LEGACY:=1}"

: "${ANSIBLE_VENV:=/opt/ansible-venv}"
: "${ANSIBLE_VENV_BIN:=${ANSIBLE_VENV}/bin/ansible-playbook}"
: "${ANSIBLE_CORE_VERSION:=2.20.5}"
: "${ANSIBLE_CORE_SPEC:=ansible-core==${ANSIBLE_CORE_VERSION}}"

# Managed fallback Python. This path must only contain real Python ${PYTHON_MAJOR_MINOR}.x.
: "${MANAGED_TARGET_PYTHON_HOME:=/opt/ansible/py312}"
: "${MANAGED_TARGET_PYTHON_PATH:=${MANAGED_TARGET_PYTHON_HOME}/bin/python}"
: "${MANAGED_TARGET_HANDOFF_MARKER:=${MANAGED_TARGET_PYTHON_HOME}/.handoff-ready}"
: "${TMP_ROOT_DIR:=/tmp/ansible/debian}"
: "${TMP_DIR:=${TMP_ROOT_DIR}}"
: "${PAGES_BASE_URL:=https://devs-guide.github.io/debian}"
: "${PLAYLIST_REL:=ansible/install.playbooks.txt}"
: "${BASE_GROUP_VARS_FILE:=all.yml}"
: "${PLATFORM_GROUP_VARS_FILE:=debian.yml}"
: "${RELEASE_GROUP_VARS_FILE:=}"

PLAYBOOK_TMP_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_DIR="${PLAYBOOK_TMP_ROOT}"
GROUP_VARS_DIR="${PLAYBOOK_TMP_ROOT}/group_vars"
PLAYLIST_PATH="${PLAYBOOK_DIR}/install.playbooks.txt"
BASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${BASE_GROUP_VARS_FILE}"
PLATFORM_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${PLATFORM_GROUP_VARS_FILE}"
RELEASE_GROUP_VARS_PATH=""
RUNTIME_SUPPORT_REFS=(packages.yml ssh.yml)
PYTHON_BOOTSTRAP_BIN=""
PYTHON_BOOTSTRAP_VERSION=""
HOST_DEBIAN_CODENAME=""
RESOLVED_RELEASE_LANE=""
BOOTSTRAP_SELECTION_MARKER="${TMP_DIR}/bootstrap.selection.env"
RUNTIME_HELPER_SOURCE_PATH="${BASH_SOURCE[0]}"
RUNTIME_HELPER_PUBLISHED_URL="${PAGES_BASE_URL}/setup/release.common.sh"
RUNTIME_HELPER_SHA256=""
declare -a ANSIBLE_EXTRA_VARS_ARGS
ANSIBLE_EXTRA_VARS_ARGS=()

if ! declare -F log >/dev/null 2>&1; then
  log() { printf '[bootstrap] %s\n' "$*" >&2; }
fi

if ! declare -F log.error >/dev/null 2>&1; then
  log.error() { printf '[bootstrap][error] %s\n' "$*" >&2; }
fi

if ! declare -F sha256.file >/dev/null 2>&1; then
  sha256.file() {
    local path="$1"

    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "${path}" | awk '{print $1}'
      return 0
    fi

    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "${path}" | awk '{print $1}'
      return 0
    fi

    return 1
  }
fi

resolve.runtime.helper.sha256() {
  if [[ -n "${RUNTIME_HELPER_SHA256}" || ! -r "${RUNTIME_HELPER_SOURCE_PATH}" ]]; then
    return 0
  fi

  RUNTIME_HELPER_SHA256="$(sha256.file "${RUNTIME_HELPER_SOURCE_PATH}" 2>/dev/null || true)"
}

log.runtime.helper.identity() {
  resolve.runtime.helper.sha256
  log "Bootstrap helper published path: ${RUNTIME_HELPER_PUBLISHED_URL}"
  log "Bootstrap helper source path: ${RUNTIME_HELPER_SOURCE_PATH}"
  if [[ -n "${RUNTIME_HELPER_SHA256}" ]]; then
    log "Bootstrap helper sha256: ${RUNTIME_HELPER_SHA256}"
  fi
  log "Bootstrap helper contract: python_min=${PYTHON_MIN_VERSION} ansible_core=${ANSIBLE_CORE_VERSION} policy=${CONTROLLER_PYTHON_POLICY} managed_fallback=${MANAGED_TARGET_PYTHON_HOME}"
}

require.root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log.error "Run as root."
    exit 1
  fi
}

require.apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log.error "apt-get not found; expected a Debian-like system."
    exit 1
  fi
}

require.debian() {
  if [[ ! -f /etc/debian_version ]]; then
    log.error "This bootstrap expects a Debian host."
    exit 1
  fi
}

version.ge() {
  local left="$1"
  local right="$2"
  [[ "$(printf '%s\n%s\n' "${right}" "${left}" | sort -V | tail -n1)" == "${left}" ]]
}

python.version.from.bin() {
  local bin="$1"
  local version_line=""

  version_line="$("${bin}" --version 2>&1)" || return 1
  python.version.normalized "${version_line}"
}

python.version.normalized() {
  local version_line="$1"
  printf '%s\n' "${version_line#Python }"
}

python.major.minor.from.version() {
  local version="$1"
  local major=""
  local minor=""

  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  printf '%s.%s\n' "${major}" "${minor}"
}

python.version.matches.controller.minimum() {
  local version="$1"

  version="$(python.version.normalized "${version}")"
  [[ -n "${version}" ]] || return 1
  version.ge "${version}" "${PYTHON_MIN_VERSION}" || return 1
}

python.version.matches.managed.fallback.contract() {
  local version="$1"
  local version_minor=""

  version="$(python.version.normalized "${version}")"
  version_minor="$(python.major.minor.from.version "${version}")"

  [[ "${version_minor}" == "${PYTHON_MAJOR_MINOR}" ]] || return 1
  version.ge "${version}" "${PYTHON_MIN_VERSION}" || return 1
}

python.can.create.venv() {
  local bin="$1"
  local probe_root=""

  probe_root="$(mktemp -d "${TMP_DIR:-/tmp}/python-venv-probe.XXXXXX")"
  if "${bin}" -m venv "${probe_root}/venv" >/dev/null 2>&1; then
    rm -rf "${probe_root}"
    return 0
  fi

  rm -rf "${probe_root}"
  return 1
}

resolve.python.candidate.bin() {
  local candidate="$1"

  if [[ -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if command -v "${candidate}" >/dev/null 2>&1; then
    command -v "${candidate}"
    return 0
  fi

  return 1
}

package.installed() {
  local package_name="$1"
  dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q 'install ok installed'
}

python.is.dpkg.owned() {
  local bin="$1"
  dpkg-query -S "${bin}" >/dev/null 2>&1
}

debian.native.python.major_minor() {
  local codename="$1"

  case "${codename}" in
    jessie) printf '%s\n' '3.4' ;;
    stretch) printf '%s\n' '3.5' ;;
    buster) printf '%s\n' '3.7' ;;
    bullseye) printf '%s\n' '3.9' ;;
    bookworm) printf '%s\n' '3.11' ;;
    trixie) printf '%s\n' '3.13' ;;
    forky|sid) printf '%s\n' '3.13' ;;
    *) return 1 ;;
  esac
}

debian.native.python.version.hint() {
  local codename="$1"

  case "${codename}" in
    jessie) printf '%s\n' '3.4.2' ;;
    stretch) printf '%s\n' '3.5.3' ;;
    buster) printf '%s\n' '3.7.3' ;;
    bullseye) printf '%s\n' '3.9.2' ;;
    bookworm) printf '%s\n' '3.11.2' ;;
    trixie) printf '%s\n' '3.13.5' ;;
    forky|sid) printf '%s\n' '3.13' ;;
    *) return 1 ;;
  esac
}

release.native.python.satisfies.controller.minimum() {
  local version_hint="$1"
  version.ge "${version_hint}" "${PYTHON_MIN_VERSION}"
}

log.python.candidate.result() {
  local resolved="$1"
  local version="$2"
  local status="$3"

  case "${status}" in
    accepted)
      log "Python candidate accepted: ${resolved} (${version})"
      ;;
    rejected)
      log "Python candidate rejected: ${resolved} (${version})"
      ;;
    unreadable)
      log "Python candidate unreadable: ${resolved}"
      ;;
  esac
}

select.system.controller.python() {
  local candidate=""
  local resolved=""
  local version=""
  local -a candidates=(
    "${SYSTEM_PYTHON_BIN}"
    "/usr/bin/python3"
    "python3"
  )

  for candidate in "${candidates[@]}"; do
    resolved="$(resolve.python.candidate.bin "${candidate}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]]; then
      continue
    fi

    version="$(python.version.from.bin "${resolved}" 2>/dev/null || true)"
    if [[ -z "${version}" ]]; then
      log.python.candidate.result "${resolved}" "" "unreadable"
      continue
    fi

    if ! python.version.matches.controller.minimum "${version}"; then
      log.python.candidate.result "${resolved}" "${version}" "rejected"
      continue
    fi

    if ! python.is.dpkg.owned "${resolved}"; then
      log "Python candidate rejected: ${resolved} (${version}) is not dpkg-owned; system provider requires distro Python"
      continue
    fi

    PYTHON_BOOTSTRAP_BIN="${resolved}"
    PYTHON_BOOTSTRAP_VERSION="$(python.version.normalized "${version}")"
    log.python.candidate.result "${resolved}" "${version}" "accepted"
    log "Using distro controller Python: ${PYTHON_BOOTSTRAP_BIN} (${PYTHON_BOOTSTRAP_VERSION})"
    return 0
  done

  return 1
}

select.managed.fallback.python() {
  local version=""

  if [[ ! -x "${MANAGED_TARGET_PYTHON_PATH}" ]]; then
    return 1
  fi

  version="$("${MANAGED_TARGET_PYTHON_PATH}" --version 2>&1 || true)"
  if [[ -z "${version}" ]]; then
    log "Existing managed fallback Python is unreadable; rebuilding: ${MANAGED_TARGET_PYTHON_PATH}"
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
    return 1
  fi

  if ! python.version.matches.managed.fallback.contract "${version}"; then
    log "Existing managed fallback Python violates fallback contract: ${version}; expected Python ${PYTHON_MAJOR_MINOR}.x >= ${PYTHON_MIN_VERSION}; rebuilding ${MANAGED_TARGET_PYTHON_HOME}"
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
    return 1
  fi

  if ! python.can.create.venv "${MANAGED_TARGET_PYTHON_PATH}"; then
    log "Existing managed fallback Python cannot create child venvs; rebuilding ${MANAGED_TARGET_PYTHON_HOME}"
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
    return 1
  fi

  PYTHON_BOOTSTRAP_BIN="${MANAGED_TARGET_PYTHON_PATH}"
  PYTHON_BOOTSTRAP_VERSION="$(python.version.normalized "${version}")"
  printf '%s\n' "${version}" > "${MANAGED_TARGET_HANDOFF_MARKER}"
  log "Using existing managed fallback Python: ${version}"
  return 0
}

select.python.bootstrap.bin() {
  case "${CONTROLLER_PYTHON_PROVIDER}" in
    system)
      select.system.controller.python
      return $?
      ;;
    managed_source)
      select.managed.fallback.python
      return $?
      ;;
    *)
      log.error "Controller Python provider is unresolved: ${CONTROLLER_PYTHON_PROVIDER}"
      log.error "resolve.controller.python.policy must run before select.python.bootstrap.bin."
      exit 1
      ;;
  esac
}

ensure.python.venv.support() {
  local version_minor=""
  local package_name=""
  local -a candidate_packages=()
  local -a install_packages=()

  if [[ -z "${PYTHON_BOOTSTRAP_BIN}" ]]; then
    log.error "PYTHON_BOOTSTRAP_BIN is empty; cannot ensure venv support."
    exit 1
  fi

  if [[ -z "${PYTHON_BOOTSTRAP_VERSION}" ]]; then
    PYTHON_BOOTSTRAP_VERSION="$(python.version.from.bin "${PYTHON_BOOTSTRAP_BIN}")"
  fi

  version_minor="$(python.major.minor.from.version "${PYTHON_BOOTSTRAP_VERSION}")"

  if python.is.dpkg.owned "${PYTHON_BOOTSTRAP_BIN}"; then
    candidate_packages=(
      "python${version_minor}-venv"
      "python3-venv"
      "python3-apt"
    )

    for package_name in "${candidate_packages[@]}"; do
      if package.installed "${package_name}"; then
        log "Python support package already installed: ${package_name}"
      else
        install_packages+=("${package_name}")
      fi
    done

    if ((${#install_packages[@]} > 0)); then
      export DEBIAN_FRONTEND=noninteractive
      log "Installing Python support packages for ${PYTHON_BOOTSTRAP_BIN}: ${install_packages[*]}"
      apt-get update -y
      apt-get install -y --no-install-recommends "${install_packages[@]}"
    fi
  else
    log "Non-distro Python selected; Debian package install is not applicable: ${PYTHON_BOOTSTRAP_BIN}"
  fi

  if ! python.can.create.venv "${PYTHON_BOOTSTRAP_BIN}"; then
    log.error "Selected controller Python cannot create venvs: ${PYTHON_BOOTSTRAP_BIN} (${PYTHON_BOOTSTRAP_VERSION})"
    if python.is.dpkg.owned "${PYTHON_BOOTSTRAP_BIN}"; then
      log.error "Expected Debian venv support package: python${version_minor}-venv or python3-venv"
    else
      log.error "For source Python, rebuild with --with-ensurepip=install."
    fi
    exit 1
  fi
}

prepare.runtime.tree() {
  mkdir -p "${PLAYBOOK_DIR}" "${GROUP_VARS_DIR}"
}

fetch.file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "${dest}")"
  log "Fetching ${url}"
  if ! wget -qO "${dest}" "${url}"; then
    log.error "Failed to fetch ${url}"
    exit 1
  fi
  if [[ ! -s "${dest}" ]]; then
    log.error "Fetched file is empty: ${url}"
    exit 1
  fi
}

fetch.optional.file() {
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

ensure.managed.fallback.python.build() {
  local managed_version=""
  export DEBIAN_FRONTEND=noninteractive

  if select.managed.fallback.python; then
    return 0
  fi

  log "No valid managed fallback Python found; building Python ${PYTHON_VERSION} from source for legacy controller runtime..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    tk-dev \
    libgdbm-dev \
    libgdbm-compat-dev \
    liblzma-dev \
    libffi-dev \
    uuid-dev \
    wget \
    curl \
    ca-certificates \
    xz-utils

  mkdir -p "${PYTHON_SOURCE_PREFIX}/src"
  if [[ ! -s "${PYTHON_SRC_ARCHIVE}" ]]; then
    fetch.file "${PYTHON_SRC_URL}" "${PYTHON_SRC_ARCHIVE}"
  fi

  if [[ ! -d "${PYTHON_SRC_DIR}" ]]; then
    tar -xzf "${PYTHON_SRC_ARCHIVE}" -C "${PYTHON_SOURCE_PREFIX}/src"
  fi

  log "Building Python ${PYTHON_VERSION}..."
  (
    cd "${PYTHON_SRC_DIR}"
    ./configure --enable-optimizations --with-ensurepip=install
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    make altinstall
  )

  PYTHON_BOOTSTRAP_BIN="${PYTHON_BIN}"
  PYTHON_BOOTSTRAP_VERSION="$(python.version.from.bin "${PYTHON_BOOTSTRAP_BIN}")"

  if ! python.version.matches.managed.fallback.contract "${PYTHON_BOOTSTRAP_VERSION}"; then
    log.error "Built Python does not satisfy managed fallback contract: ${PYTHON_BOOTSTRAP_BIN} (${PYTHON_BOOTSTRAP_VERSION})"
    exit 1
  fi

  ensure.python.venv.support

  mkdir -p "$(dirname "${MANAGED_TARGET_PYTHON_HOME}")"
  rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
  "${PYTHON_BOOTSTRAP_BIN}" -m venv "${MANAGED_TARGET_PYTHON_HOME}"

  managed_version="$("${MANAGED_TARGET_PYTHON_PATH}" --version 2>&1)"
  if ! python.version.matches.managed.fallback.contract "${managed_version}"; then
    log.error "Managed fallback Python was created with wrong version: ${managed_version}; expected Python ${PYTHON_MAJOR_MINOR}.x >= ${PYTHON_MIN_VERSION}"
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
    exit 1
  fi

  if ! python.can.create.venv "${MANAGED_TARGET_PYTHON_PATH}"; then
    log.error "Managed fallback Python was created but cannot create child venvs: ${MANAGED_TARGET_PYTHON_PATH}"
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
    exit 1
  fi

  printf '%s\n' "${managed_version}" > "${MANAGED_TARGET_HANDOFF_MARKER}"
  PYTHON_BOOTSTRAP_BIN="${MANAGED_TARGET_PYTHON_PATH}"
  PYTHON_BOOTSTRAP_VERSION="$(python.version.normalized "${managed_version}")"
  log "Managed fallback Python ready: ${managed_version}"
}

ensure.python312() {
  ensure.managed.fallback.python.build
}

resolve.release.groupvars.file() {
  local candidate="${RELEASE_GROUP_VARS_FILE:-}"

  if [[ -n "${candidate}" ]]; then
    candidate="${candidate##*/}"
    case "${candidate}" in
      buster.yml|trixie.yml) ;;
      *)
        log.error "Unsupported explicit DEBIAN_RELEASE_GROUP_VARS_FILE: ${candidate}"
        log.error "Supported release overlays: buster.yml, trixie.yml"
        exit 1
        ;;
    esac
    RELEASE_GROUP_VARS_FILE="${candidate}"
    RESOLVED_RELEASE_LANE="${candidate%.yml}"
    log "Using explicit Debian release lane override: ${RELEASE_GROUP_VARS_FILE}"
    return
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    HOST_DEBIAN_CODENAME="${VERSION_CODENAME:-}"
  fi

  case "${HOST_DEBIAN_CODENAME}" in
    buster)
      RELEASE_GROUP_VARS_FILE="buster.yml"
      RESOLVED_RELEASE_LANE="buster"
      ;;
    trixie)
      RELEASE_GROUP_VARS_FILE="trixie.yml"
      RESOLVED_RELEASE_LANE="trixie"
      ;;
    "")
      log.error "Unable to detect Debian VERSION_CODENAME from /etc/os-release."
      log.error "Set DEBIAN_RELEASE_GROUP_VARS_FILE explicitly."
      exit 1
      ;;
    *)
      log.error "Unsupported Debian release codename: ${HOST_DEBIAN_CODENAME}"
      log.error "Supported release overlays: buster, trixie"
      log.error "Native Python policy map knows additional Debian releases, but this repo currently only ships buster/trixie release overlays."
      log.error "Set DEBIAN_RELEASE_GROUP_VARS_FILE explicitly if needed."
      exit 1
      ;;
  esac

  log "Resolved Debian release lane: ${RESOLVED_RELEASE_LANE} (${RELEASE_GROUP_VARS_FILE})"
}

resolve.controller.python.policy() {
  local codename="${RESOLVED_RELEASE_LANE:-${HOST_DEBIAN_CODENAME:-}}"
  local native_minor=""
  local native_hint=""

  if [[ -z "${codename}" ]]; then
    log.error "Cannot resolve controller Python policy before Debian release lane is known."
    exit 1
  fi

  native_minor="$(debian.native.python.major_minor "${codename}" 2>/dev/null || true)"
  native_hint="$(debian.native.python.version.hint "${codename}" 2>/dev/null || true)"

  if [[ -z "${native_minor}" || -z "${native_hint}" ]]; then
    log.error "No native Python policy mapping for Debian release: ${codename}"
    log.error "Add ${codename} to debian.native.python.major_minor() and debian.native.python.version.hint()."
    exit 1
  fi

  CONTROLLER_PYTHON_NATIVE_MAJOR_MINOR="${native_minor}"
  CONTROLLER_PYTHON_NATIVE_VERSION_HINT="${native_hint}"

  case "${CONTROLLER_PYTHON_POLICY}" in
    auto)
      if release.native.python.satisfies.controller.minimum "${native_hint}"; then
        CONTROLLER_PYTHON_PROVIDER="system"
        CONTROLLER_PYTHON_REBUILD_FOR_LEGACY=0
      else
        CONTROLLER_PYTHON_PROVIDER="managed_source"
        CONTROLLER_PYTHON_REBUILD_FOR_LEGACY=1
      fi
      ;;
    system)
      CONTROLLER_PYTHON_PROVIDER="system"
      CONTROLLER_PYTHON_REBUILD_FOR_LEGACY=0
      ;;
    managed_source)
      CONTROLLER_PYTHON_PROVIDER="managed_source"
      CONTROLLER_PYTHON_REBUILD_FOR_LEGACY=1
      ;;
    *)
      log.error "Unsupported CONTROLLER_PYTHON_POLICY=${CONTROLLER_PYTHON_POLICY}; expected auto, system, or managed_source."
      exit 1
      ;;
  esac

  log "Controller Python policy: release=${codename} native_python=${native_hint} minimum=${PYTHON_MIN_VERSION} provider=${CONTROLLER_PYTHON_PROVIDER}"
}

write.bootstrap.selection.marker() {
  mkdir -p "${TMP_DIR}"
  resolve.runtime.helper.sha256
  cat > "${BOOTSTRAP_SELECTION_MARKER}" <<EOF
python_bootstrap_bin=${PYTHON_BOOTSTRAP_BIN}
python_bootstrap_version=${PYTHON_BOOTSTRAP_VERSION}
controller_python_policy=${CONTROLLER_PYTHON_POLICY}
controller_python_provider=${CONTROLLER_PYTHON_PROVIDER}
controller_python_bin=${CONTROLLER_PYTHON_BIN}
controller_python_version=${CONTROLLER_PYTHON_VERSION}
controller_python_native_major_minor=${CONTROLLER_PYTHON_NATIVE_MAJOR_MINOR}
controller_python_native_version_hint=${CONTROLLER_PYTHON_NATIVE_VERSION_HINT}
controller_python_rebuild_for_legacy=${CONTROLLER_PYTHON_REBUILD_FOR_LEGACY}
managed_target_python_home=${MANAGED_TARGET_PYTHON_HOME}
managed_target_python_path=${MANAGED_TARGET_PYTHON_PATH}
host_debian_codename=${HOST_DEBIAN_CODENAME}
resolved_release_lane=${RESOLVED_RELEASE_LANE}
release_group_vars_file=${RELEASE_GROUP_VARS_FILE}
runtime_helper_published_url=${RUNTIME_HELPER_PUBLISHED_URL}
runtime_helper_source_path=${RUNTIME_HELPER_SOURCE_PATH}
runtime_helper_sha256=${RUNTIME_HELPER_SHA256}
EOF
  reset.ansible.extra.vars
  log "Bootstrap selection marker: ${BOOTSTRAP_SELECTION_MARKER}"
}

ensure.controller.python() {
  case "${CONTROLLER_PYTHON_PROVIDER}" in
    system)
      if ! select.system.controller.python; then
        log.error "Release policy requires system Python, but no valid distro Python >= ${PYTHON_MIN_VERSION} was found."
        log.error "Detected release=${RESOLVED_RELEASE_LANE:-unknown} native_python_hint=${CONTROLLER_PYTHON_NATIVE_VERSION_HINT:-unknown}"
        exit 1
      fi
      ensure.python.venv.support
      CONTROLLER_PYTHON_BIN="${PYTHON_BOOTSTRAP_BIN}"
      CONTROLLER_PYTHON_VERSION="${PYTHON_BOOTSTRAP_VERSION}"
      log "Controller Python ready from system: ${CONTROLLER_PYTHON_BIN} (${CONTROLLER_PYTHON_VERSION})"
      ;;
    managed_source)
      ensure.managed.fallback.python.build
      CONTROLLER_PYTHON_BIN="${PYTHON_BOOTSTRAP_BIN}"
      CONTROLLER_PYTHON_VERSION="${PYTHON_BOOTSTRAP_VERSION}"
      log "Controller Python ready from managed fallback: ${CONTROLLER_PYTHON_BIN} (${CONTROLLER_PYTHON_VERSION})"
      ;;
    *)
      log.error "Controller Python provider is unresolved: ${CONTROLLER_PYTHON_PROVIDER}"
      exit 1
      ;;
  esac
}

ensure.managed.target.python() {
  ensure.controller.python
}

ansible.venv.python.version() {
  [[ -x "${ANSIBLE_VENV}/bin/python" ]] || return 1
  "${ANSIBLE_VENV}/bin/python" --version 2>&1 | sed 's/^Python //'
}

ansible.venv.python.matches.controller.minimum() {
  local version=""
  version="$(ansible.venv.python.version 2>/dev/null || true)"
  [[ -n "${version}" ]] || return 1
  python.version.matches.controller.minimum "${version}"
}

ansible.venv.core.version() {
  local header=""
  local parsed=""
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || return 1
  header="$("${ANSIBLE_VENV_BIN}" --version 2>/dev/null | head -n1 || true)"
  [[ -n "${header}" ]] || return 1
  parsed="$(printf '%s\n' "${header}" | sed -nE 's/.*\[core ([^]]+)\].*/\1/p')"
  [[ -n "${parsed}" ]] || return 1
  printf '%s\n' "${parsed}"
}

ansible.venv.core.matches.contract() {
  local current_core=""
  [[ -x "${ANSIBLE_VENV_BIN}" ]] || return 1
  current_core="$(ansible.venv.core.version 2>/dev/null || true)"
  [[ -n "${current_core}" ]] || return 1
  [[ "${current_core}" == "${ANSIBLE_CORE_VERSION}" ]]
}

ensure.managed.ansible() {
  export DEBIAN_FRONTEND=noninteractive
  ensure.controller.python

  if [[ -x "${ANSIBLE_VENV_BIN}" ]]; then
    if ansible.venv.core.matches.contract && ansible.venv.python.matches.controller.minimum; then
      log "Using existing managed Ansible: $("${ANSIBLE_VENV_BIN}" --version | head -n1) with Python $(ansible.venv.python.version)"
      return
    fi

    log "Existing managed Ansible venv is stale or incompatible; rebuilding ${ANSIBLE_VENV}"
    log "Existing Ansible check: $("${ANSIBLE_VENV_BIN}" --version 2>/dev/null | head -n1 || true)"
    log "Existing Python check: $(ansible.venv.python.version 2>/dev/null || true)"
    rm -rf "${ANSIBLE_VENV}"
  fi

  ensure.python.venv.support
  if ! python.can.create.venv "${CONTROLLER_PYTHON_BIN}"; then
    log.error "Controller Python cannot create Ansible venv: ${CONTROLLER_PYTHON_BIN}"
    exit 1
  fi
  mkdir -p "${ANSIBLE_VENV}"
  "${CONTROLLER_PYTHON_BIN}" -m venv "${ANSIBLE_VENV}"
  "${ANSIBLE_VENV}/bin/pip" install --upgrade pip setuptools wheel
  "${ANSIBLE_VENV}/bin/pip" install --upgrade "${ANSIBLE_CORE_SPEC}" passlib
  "${ANSIBLE_VENV}/bin/ansible-galaxy" collection install community.general:8.6.0

  if ! ansible.venv.core.matches.contract; then
    log.error "Managed Ansible venv was created, but Ansible core version does not match ${ANSIBLE_CORE_VERSION}."
    "${ANSIBLE_VENV_BIN}" --version || true
    exit 1
  fi

  if ! ansible.venv.python.matches.controller.minimum; then
    log.error "Managed Ansible venv was created, but its Python does not satisfy ${PYTHON_MIN_VERSION}."
    "${ANSIBLE_VENV}/bin/python" --version || true
    exit 1
  fi

  log "Managed Ansible ready: $("${ANSIBLE_VENV_BIN}" --version | head -n1) with Python $(ansible.venv.python.version)"
}

ensure.local.ansible() {
  local local_python=""
  local local_python_version=""
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -y
  apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-apt \
    ca-certificates \
    curl \
    wget

  local_python="$(command -v python3)"
  local_python_version="$(python.version.from.bin "${local_python}")"
  if ! python.version.matches.controller.minimum "${local_python_version}"; then
    log.error "Local system python3 (${local_python_version}) is below controller minimum ${PYTHON_MIN_VERSION}. Use managed bootstrap path instead."
    exit 1
  fi

  PYTHON_BOOTSTRAP_BIN="${local_python}"
  PYTHON_BOOTSTRAP_VERSION="${local_python_version}"
  CONTROLLER_PYTHON_BIN="${local_python}"
  CONTROLLER_PYTHON_VERSION="${local_python_version}"
  ensure.python.venv.support

  if [[ -x "${ANSIBLE_VENV_BIN}" ]]; then
    if ansible.venv.core.matches.contract && ansible.venv.python.matches.controller.minimum; then
      log "Using existing local Ansible: $("${ANSIBLE_VENV_BIN}" --version | head -n1) with Python $(ansible.venv.python.version)"
      return
    fi
    rm -rf "${ANSIBLE_VENV}"
  fi

  mkdir -p "${ANSIBLE_VENV}"
  "${local_python}" -m venv "${ANSIBLE_VENV}"
  "${ANSIBLE_VENV}/bin/pip" install --upgrade pip setuptools wheel
  "${ANSIBLE_VENV}/bin/pip" install --upgrade "${ANSIBLE_CORE_SPEC}" passlib
  "${ANSIBLE_VENV}/bin/ansible-galaxy" collection install community.general:8.6.0
  log "Local Ansible ready: $("${ANSIBLE_VENV_BIN}" --version | head -n1) with Python $(ansible.venv.python.version)"
}

reset.ansible.extra.vars() {
  ANSIBLE_EXTRA_VARS_ARGS=()

  if [[ -f "${BASE_GROUP_VARS_PATH}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "@${BASE_GROUP_VARS_PATH}")
  fi

  if [[ -f "${PLATFORM_GROUP_VARS_PATH}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "@${PLATFORM_GROUP_VARS_PATH}")
  fi

  if [[ -n "${RELEASE_GROUP_VARS_PATH}" && -f "${RELEASE_GROUP_VARS_PATH}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "@${RELEASE_GROUP_VARS_PATH}")
  fi

  if [[ -n "${CONTROLLER_PYTHON_BIN}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "controller_python_bin=${CONTROLLER_PYTHON_BIN}")
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "ansible_python_interpreter_controller=${CONTROLLER_PYTHON_BIN}")
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "ansible_python_interpreter_managed=${CONTROLLER_PYTHON_BIN}")
  fi

  if [[ -n "${CONTROLLER_PYTHON_VERSION}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "controller_python_version=${CONTROLLER_PYTHON_VERSION}")
  fi

  if [[ -n "${CONTROLLER_PYTHON_PROVIDER}" ]]; then
    ANSIBLE_EXTRA_VARS_ARGS+=(-e "bootstrap_controller_python_provider=${CONTROLLER_PYTHON_PROVIDER}")
  fi
}

use.local.runtime.tree() {
  local repo_root="$1"
  PLAYBOOK_TMP_ROOT="${repo_root}/ansible"
  PLAYBOOK_DIR="${PLAYBOOK_TMP_ROOT}"
  GROUP_VARS_DIR="${PLAYBOOK_TMP_ROOT}/group_vars"
  PLAYLIST_PATH="${PLAYBOOK_DIR}/install.playbooks.txt"
  BASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${BASE_GROUP_VARS_FILE}"
  PLATFORM_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${PLATFORM_GROUP_VARS_FILE}"
  RELEASE_GROUP_VARS_PATH=""
  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    RELEASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${RELEASE_GROUP_VARS_FILE}"
  fi
  reset.ansible.extra.vars
}

use.remote.runtime.tree() {
  PLAYBOOK_TMP_ROOT="${TMP_DIR}/ansible"
  PLAYBOOK_DIR="${PLAYBOOK_TMP_ROOT}"
  GROUP_VARS_DIR="${PLAYBOOK_TMP_ROOT}/group_vars"
  PLAYLIST_PATH="${PLAYBOOK_DIR}/install.playbooks.txt"
  BASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${BASE_GROUP_VARS_FILE}"
  PLATFORM_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${PLATFORM_GROUP_VARS_FILE}"
  RELEASE_GROUP_VARS_PATH=""
  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    RELEASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${RELEASE_GROUP_VARS_FILE}"
  fi
  prepare.runtime.tree
}

fetch.groupvars() {
  fetch.file "${PAGES_BASE_URL}/ansible/group_vars/${BASE_GROUP_VARS_FILE}" "${BASE_GROUP_VARS_PATH}"
  fetch.file "${PAGES_BASE_URL}/ansible/group_vars/${PLATFORM_GROUP_VARS_FILE}" "${PLATFORM_GROUP_VARS_PATH}"

  if [[ -n "${RELEASE_GROUP_VARS_FILE}" ]]; then
    fetch.optional.file \
      "${PAGES_BASE_URL}/ansible/group_vars/${RELEASE_GROUP_VARS_FILE}" \
      "${RELEASE_GROUP_VARS_PATH}" || true
  fi

  reset.ansible.extra.vars
}

fetch.playlist() {
  fetch.file "${PAGES_BASE_URL}/${PLAYLIST_REL}" "${PLAYLIST_PATH}"
}

fetch.playbook() {
  local ref="$1"
  local remote_rel="$ref"
  local dest=""

  dest="${PLAYBOOK_TMP_ROOT}/${remote_rel}"
  fetch.file "${PAGES_BASE_URL}/ansible/${remote_rel}" "${dest}"
  printf '%s\n' "${dest}"
}

fetch.runtime.support.files() {
  local ref=""
  local dest=""

  for ref in "${RUNTIME_SUPPORT_REFS[@]}"; do
    dest="${PLAYBOOK_TMP_ROOT}/${ref}"
    if [[ -f "${dest}" ]]; then
      continue
    fi
    fetch.file "${PAGES_BASE_URL}/ansible/${ref}" "${dest}"
  done
}

run.playbooks() {
  local -a playbook_paths=("$@")
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${ANSIBLE_EXTRA_VARS_ARGS[@]}" "${playbook_paths[@]}"
}

run.playlist() {
  local ref=""
  local playbook_path=""
  local -a playbook_paths=()

  fetch.runtime.support.files

  while IFS= read -r ref; do
    ref="${ref%%$'\r'}"
    ref="$(printf '%s' "${ref}" | sed 's/[[:space:]]*$//')"
    [[ -z "${ref}" || "${ref}" =~ ^[[:space:]]*# ]] && continue
    playbook_path="$(fetch.playbook "${ref}")"
    playbook_paths+=("${playbook_path}")
  done < "${PLAYLIST_PATH}"

  if ((${#playbook_paths[@]} == 0)); then
    log.error "Playlist is empty: ${PLAYLIST_PATH}"
    exit 1
  fi

  run.playbooks "${playbook_paths[@]}"
}
