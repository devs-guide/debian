#!/usr/bin/env bash

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
: "${TMP_DIR:=/tmp/devsguide-debian}"
: "${PAGES_BASE_URL:=https://devs-guide.github.io/debian}"
: "${PLAYLIST_REL:=ansible/install.playbooks.txt}"
: "${BASE_GROUP_VARS_FILE:=all.yml}"
: "${PLATFORM_GROUP_VARS_FILE:=debian.yml}"
: "${RELEASE_GROUP_VARS_FILE:=}"

PLAYBOOK_TMP_ROOT="${TMP_DIR}/ansible"
PLAYBOOK_DIR="${PLAYBOOK_TMP_ROOT}"
GROUP_VARS_DIR="${PLAYBOOK_TMP_ROOT}/group_vars"
PLAYLIST_PATH="${PLAYBOOK_DIR}/install.playbooks.txt"
BASE_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${BASE_GROUP_VARS_FILE}"
PLATFORM_GROUP_VARS_PATH="${GROUP_VARS_DIR}/${PLATFORM_GROUP_VARS_FILE}"
RELEASE_GROUP_VARS_PATH=""
PYTHON_BOOTSTRAP_BIN=""
declare -a ANSIBLE_EXTRA_VARS_ARGS
ANSIBLE_EXTRA_VARS_ARGS=()

if ! declare -F log >/dev/null 2>&1; then
  log() { printf '[bootstrap] %s\n' "$*" >&2; }
fi

if ! declare -F log.error >/dev/null 2>&1; then
  log.error() { printf '[bootstrap][error] %s\n' "$*" >&2; }
fi

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

  if command -v "python${PYTHON_MAJOR_MINOR}" >/dev/null 2>&1; then
    PYTHON_BOOTSTRAP_BIN="$(command -v "python${PYTHON_MAJOR_MINOR}")"
    log "Using existing Python: $("${PYTHON_BOOTSTRAP_BIN}" --version 2>&1)"
    return
  fi

  if [[ -x "${PYTHON_BIN}" ]]; then
    PYTHON_BOOTSTRAP_BIN="${PYTHON_BIN}"
    log "Using local Python: $("${PYTHON_BOOTSTRAP_BIN}" --version 2>&1)"
    return
  fi

  log "Installing Python ${PYTHON_VERSION} build prerequisites..."
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
  mkdir -p "$(dirname "${MANAGED_TARGET_PYTHON_HOME}")"
  "${PYTHON_BOOTSTRAP_BIN}" -m venv "${MANAGED_TARGET_PYTHON_HOME}"
  managed_version="$("${MANAGED_TARGET_PYTHON_PATH}" --version 2>&1)"
  printf '%s\n' "${managed_version}" > "${MANAGED_TARGET_HANDOFF_MARKER}"
  PYTHON_BOOTSTRAP_BIN="${MANAGED_TARGET_PYTHON_PATH}"
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
