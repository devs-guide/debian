#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/release.common.sh

set -euo pipefail

: "${PYTHON_VERSION:=3.12.3}"
: "${PYTHON_MAJOR_MINOR:=3.12}"
: "${PYTHON_SOURCE_PREFIX:=/usr/local}"
: "${PYTHON_BIN:=${PYTHON_SOURCE_PREFIX}/bin/python${PYTHON_MAJOR_MINOR}}"
: "${PYTHON_SRC_DIR:=${PYTHON_SOURCE_PREFIX}/src/Python-${PYTHON_VERSION}}"
: "${PYTHON_SRC_ARCHIVE:=${PYTHON_SRC_DIR}.tgz}"
: "${PYTHON_SRC_URL:=https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz}"
: "${ANSIBLE_VENV:=/opt/ansible-venv}"
: "${ANSIBLE_VENV_BIN:=${ANSIBLE_VENV}/bin/ansible-playbook}"
: "${ANSIBLE_CORE_VERSION:=2.20.5}"
: "${ANSIBLE_CORE_SPEC:=ansible-core==${ANSIBLE_CORE_VERSION}}"
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
: "${PYTHON_MIN_VERSION:=3.12.3}"

PLAYBOOK_TMP_ROOT="${TMP_DIR}/runtime"
PLAYBOOK_DIR="${PLAYBOOK_TMP_ROOT}"
GROUP_VARS_DIR="${PLAYBOOK_TMP_ROOT}/group_vars"
PLAYLIST_PATH="${PLAYBOOK_DIR}/install.playbooks.txt"
BASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${BASE_GROUP_VARS_FILE}"
PLATFORM_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${PLATFORM_GROUP_VARS_FILE}"
RELEASE_GROUP_VARS_PATH=""
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
  log "Bootstrap helper contract: python_min=${PYTHON_MIN_VERSION} ansible_core=${ANSIBLE_CORE_VERSION} managed_target=${MANAGED_TARGET_PYTHON_HOME}"
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

log.python.candidate.result() {
  local resolved="$1"
  local version="$2"
  local status="$3"

  case "${status}" in
    accepted)
      log "Python candidate accepted: ${resolved} (${version}) >= ${PYTHON_MIN_VERSION}"
      ;;
    rejected)
      log "Python candidate rejected: ${resolved} (${version}) < ${PYTHON_MIN_VERSION}"
      ;;
    unreadable)
      log "Python candidate unreadable: ${resolved}"
      ;;
  esac
}

select.python.bootstrap.bin() {
  local candidate=""
  local resolved=""
  local version=""
  local -a candidates=(
    "/usr/bin/python3"
    "python3"
    "/usr/local/bin/python3"
    "python${PYTHON_MAJOR_MINOR}"
    "${PYTHON_BIN}"
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

    if version.ge "${version}" "${PYTHON_MIN_VERSION}"; then
      PYTHON_BOOTSTRAP_BIN="${resolved}"
      PYTHON_BOOTSTRAP_VERSION="${version}"
      log.python.candidate.result "${resolved}" "${version}" "accepted"
      log "Using compatible system Python: ${PYTHON_BOOTSTRAP_BIN} (${PYTHON_BOOTSTRAP_VERSION})"
      return 0
    fi

    log.python.candidate.result "${resolved}" "${version}" "rejected"
  done

  return 1
}

ensure.python.venv.support() {
  local version_minor=""
  local package_name=""
  local -a candidate_packages=()
  local -a missing_packages=()

  if ! dpkg-query -S "${PYTHON_BOOTSTRAP_BIN}" >/dev/null 2>&1; then
    log "Skipping Debian venv package install for non-distro Python: ${PYTHON_BOOTSTRAP_BIN}"
    return 0
  fi

  if [[ -z "${PYTHON_BOOTSTRAP_VERSION}" ]]; then
    PYTHON_BOOTSTRAP_VERSION="$(python.version.from.bin "${PYTHON_BOOTSTRAP_BIN}")"
  fi

  version_minor="$(python.major.minor.from.version "${PYTHON_BOOTSTRAP_VERSION}")"
  candidate_packages=(
    "python${version_minor}-venv"
    "python3-venv"
  )

  for package_name in "${candidate_packages[@]}"; do
    if package.installed "${package_name}"; then
      log "Python venv package already installed: ${package_name}"
      continue
    fi
    missing_packages+=("${package_name}")
  done

  if ((${#missing_packages[@]} == 0)); then
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  log "Installing Python venv support packages: ${missing_packages[*]}"
  apt-get update -y
  apt-get install -y --no-install-recommends "${missing_packages[@]}"
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

ensure.python312() {
  export DEBIAN_FRONTEND=noninteractive

  if select.python.bootstrap.bin; then
    return
  fi

  log "No compatible system Python found; building Python ${PYTHON_VERSION} from source..."
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
  log "Built Python ready: ${PYTHON_BOOTSTRAP_BIN} (${PYTHON_BOOTSTRAP_VERSION})"
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
      log.error "Set DEBIAN_RELEASE_GROUP_VARS_FILE explicitly if needed."
      exit 1
      ;;
  esac

  log "Resolved Debian release lane: ${RESOLVED_RELEASE_LANE} (${RELEASE_GROUP_VARS_FILE})"
}

write.bootstrap.selection.marker() {
  mkdir -p "${TMP_DIR}"
  resolve.runtime.helper.sha256
  cat > "${BOOTSTRAP_SELECTION_MARKER}" <<EOF
python_bootstrap_bin=${PYTHON_BOOTSTRAP_BIN}
python_bootstrap_version=${PYTHON_BOOTSTRAP_VERSION}
host_debian_codename=${HOST_DEBIAN_CODENAME}
resolved_release_lane=${RESOLVED_RELEASE_LANE}
release_group_vars_file=${RELEASE_GROUP_VARS_FILE}
runtime_helper_published_url=${RUNTIME_HELPER_PUBLISHED_URL}
runtime_helper_source_path=${RUNTIME_HELPER_SOURCE_PATH}
runtime_helper_sha256=${RUNTIME_HELPER_SHA256}
EOF
  log "Bootstrap selection marker: ${BOOTSTRAP_SELECTION_MARKER}"
}

ensure.managed.target.python() {
  local managed_version=""

  if [[ -x "${MANAGED_TARGET_PYTHON_PATH}" ]]; then
    if managed_version="$("${MANAGED_TARGET_PYTHON_PATH}" --version 2>&1)"; then
      PYTHON_BOOTSTRAP_BIN="${MANAGED_TARGET_PYTHON_PATH}"
      printf '%s\n' "${managed_version}" > "${MANAGED_TARGET_HANDOFF_MARKER}"
      log "Using existing managed target Python: ${managed_version}"
      return
    fi
    rm -rf "${MANAGED_TARGET_PYTHON_HOME}"
  fi

  ensure.python312
  ensure.python.venv.support
  mkdir -p "$(dirname "${MANAGED_TARGET_PYTHON_HOME}")"
  "${PYTHON_BOOTSTRAP_BIN}" -m venv "${MANAGED_TARGET_PYTHON_HOME}"
  managed_version="$("${MANAGED_TARGET_PYTHON_PATH}" --version 2>&1)"
  printf '%s\n' "${managed_version}" > "${MANAGED_TARGET_HANDOFF_MARKER}"
  PYTHON_BOOTSTRAP_BIN="${MANAGED_TARGET_PYTHON_PATH}"
  PYTHON_BOOTSTRAP_VERSION="${managed_version#Python }"
  log "Managed target Python ready: ${managed_version}"
}

ensure.managed.ansible() {
  export DEBIAN_FRONTEND=noninteractive

  if [[ -x "${ANSIBLE_VENV_BIN}" ]]; then
    if "${ANSIBLE_VENV_BIN}" --version 2>/dev/null | head -n1 | grep -q "core ${ANSIBLE_CORE_VERSION}\$"; then
      ensure.managed.target.python
      log "Using existing managed Ansible: $("${ANSIBLE_VENV_BIN}" --version | head -n1)"
      return
    fi
    rm -rf "${ANSIBLE_VENV}"
  fi

  ensure.managed.target.python
  ensure.python.venv.support
  mkdir -p "${ANSIBLE_VENV}"
  "${PYTHON_BOOTSTRAP_BIN}" -m venv "${ANSIBLE_VENV}"
  "${ANSIBLE_VENV}/bin/pip" install --upgrade pip setuptools wheel
  "${ANSIBLE_VENV}/bin/pip" install --upgrade "${ANSIBLE_CORE_SPEC}" passlib
  "${ANSIBLE_VENV}/bin/ansible-galaxy" collection install community.general:8.6.0
  log "Managed Ansible ready: $("${ANSIBLE_VENV_BIN}" --version | head -n1)"
}

ensure.local.ansible() {
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -y
  apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-apt \
    ca-certificates \
    curl \
    wget

  if [[ -x "${ANSIBLE_VENV_BIN}" ]]; then
    if "${ANSIBLE_VENV_BIN}" --version 2>/dev/null | head -n1 | grep -q "core ${ANSIBLE_CORE_VERSION}\$"; then
      log "Using existing local Ansible: $("${ANSIBLE_VENV_BIN}" --version | head -n1)"
      return
    fi
    rm -rf "${ANSIBLE_VENV}"
  fi

  mkdir -p "${ANSIBLE_VENV}"
  python3 -m venv "${ANSIBLE_VENV}"
  "${ANSIBLE_VENV}/bin/pip" install --upgrade pip setuptools wheel
  "${ANSIBLE_VENV}/bin/pip" install --upgrade "${ANSIBLE_CORE_SPEC}" passlib
  "${ANSIBLE_VENV}/bin/ansible-galaxy" collection install community.general:8.6.0
  log "Local Ansible ready: $("${ANSIBLE_VENV_BIN}" --version | head -n1)"
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

run.playbook() {
  local playbook_path="$1"
  shift || true
  "${ANSIBLE_VENV_BIN}" -i localhost, -c local "${ANSIBLE_EXTRA_VARS_ARGS[@]}" "$@" "${playbook_path}"
}

run.playlist() {
  local ref=""
  local playbook_path=""

  while IFS= read -r ref; do
    ref="${ref%%$'\r'}"
    ref="$(printf '%s' "${ref}" | sed 's/[[:space:]]*$//')"
    [[ -z "${ref}" || "${ref}" =~ ^[[:space:]]*# ]] && continue
    playbook_path="$(fetch.playbook "${ref}")"
    run.playbook "${playbook_path}"
  done < "${PLAYLIST_PATH}"
}
