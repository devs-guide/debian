#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/runner.common.sh
# Shared privilege and per-run staging contract for setup entrypoints.

set -euo pipefail

: "${RUNNER_RUNTIME_DIR:=}"
: "${RUNNER_RUNTIME_FEATURE:=}"
: "${RUNNER_RUNTIME_ACTIVE:=0}"
: "${RUNNER_SUDO_AUTHENTICATED:=0}"
: "${RUNNER_TTY_PATH:=/dev/tty}"
: "${RUNNER_LOCAL_REPO_ROOT:=}"
: "${RUNNER_STAGE_SOURCE:=}"

if ! declare -F log >/dev/null 2>&1; then
  log() { printf '[setup.runner] %s\n' "$*" >&2; }
fi

if ! declare -F log.error >/dev/null 2>&1; then
  log.error() { printf '[setup.runner][error] %s\n' "$*" >&2; }
fi

if ! declare -F log.warn >/dev/null 2>&1; then
  log.warn() { printf '[setup.runner][warn] %s\n' "$*" >&2; }
fi

runner.euid() {
  printf '%s\n' "${EUID:-$(id -u)}"
}

runner.have.controlling.tty() {
  [[ -r "${RUNNER_TTY_PATH}" && -w "${RUNNER_TTY_PATH}" ]]
}

runner.confirm.exact() {
  local summary="$1"
  local confirmation="$2"
  local response=""

  if ! runner.have.controlling.tty; then
    log.error "Explicit operator confirmation requires a usable /dev/tty."
    log.error "Run from an interactive terminal or allocate one with ssh -t."
    return 1
  fi

  printf '\n%s\n' "${summary}" >"${RUNNER_TTY_PATH}"
  printf 'Type exactly: %s\n> ' "${confirmation}" >"${RUNNER_TTY_PATH}"
  if ! IFS= read -r response <"${RUNNER_TTY_PATH}"; then
    log.error "Operator confirmation was not received."
    return 1
  fi
  if [[ "${response}" != "${confirmation}" ]]; then
    log.error "Operator confirmation did not match; no changes were made."
    return 1
  fi
}

runner.runtime.path.is.safe() {
  local feature="$1"
  local path="$2"
  local basename=""
  local suffix=""

  [[ "${feature}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
  [[ -n "${path}" && "${path}" == /* && "${path}" != / && "${path}" != /tmp ]] || return 1

  basename="${path##*/}"
  [[ "${basename}" == "devs-guide-${feature}."* ]] || return 1
  suffix="${basename#devs-guide-${feature}.}"
  [[ "${suffix}" =~ ^[A-Za-z0-9]+$ ]]
}

runner.install.cleanup.trap() {
  trap 'runner.cleanup.runtime || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

runner.adopt.runtime() {
  local feature="$1"
  local path="$2"
  local resolved=""

  [[ -d "${path}" ]] || {
    log.error "Runner runtime directory is unavailable: ${path}"
    return 1
  }
  resolved="$(cd "${path}" && pwd -P)"
  runner.runtime.path.is.safe "${feature}" "${resolved}" || {
    log.error "Refusing unsafe runner runtime directory: ${resolved}"
    return 1
  }
  if [[ "$(runner.euid)" -ne 0 && ! -O "${resolved}" ]]; then
    log.error "Runner runtime directory is not owned by the invoking user: ${resolved}"
    return 1
  fi

  chmod 0700 "${resolved}"
  RUNNER_RUNTIME_FEATURE="${feature}"
  RUNNER_RUNTIME_DIR="${resolved}"
  RUNNER_RUNTIME_ACTIVE=1
  runner.install.cleanup.trap
}

runner.create.runtime() {
  local feature="$1"
  local parent="${2:-/tmp}"
  local resolved_parent=""
  local runtime=""

  [[ -z "${RUNNER_RUNTIME_DIR}" && "${RUNNER_RUNTIME_ACTIVE}" != 1 ]] || {
    log.error "Runner runtime has already been initialized: ${RUNNER_RUNTIME_DIR}"
    return 1
  }
  [[ "${parent}" == /* && "${parent}" != / && -d "${parent}" && -w "${parent}" ]] || {
    log.error "Runner temporary parent must be an existing writable absolute directory other than /: ${parent}"
    return 1
  }
  resolved_parent="$(cd "${parent}" && pwd -P)"
  runtime="$(mktemp -d "${resolved_parent%/}/devs-guide-${feature}.XXXXXX")"
  runner.adopt.runtime "${feature}" "${runtime}"
}

runner.relative.path.is.safe() {
  local path="${1:-}"
  local segment=""
  local -a segments=()

  [[ -n "${path}" && "${path}" != /* && "${path}" != */ && "${path}" != *'//'*
    && "${path}" != *$'\n'* && "${path}" != *$'\r'* ]] || return 1

  IFS='/' read -r -a segments <<< "${path}"
  ((${#segments[@]} > 0)) || return 1
  for segment in "${segments[@]}"; do
    [[ "${segment}" =~ ^[A-Za-z0-9][A-Za-z0-9._+@-]*$ ]] || return 1
    [[ "${segment}" != . && "${segment}" != .. ]] || return 1
  done
}

runner.prepare.stage.root() {
  local requested="${1:-}"
  local runtime=""
  local resolved=""

  [[ -n "${RUNNER_RUNTIME_DIR:-}" && -d "${RUNNER_RUNTIME_DIR}" ]] || {
    log.error "Runner runtime must be initialized before staging files."
    return 1
  }
  runtime="$(cd "${RUNNER_RUNTIME_DIR}" && pwd -P)"
  [[ -n "${requested}" && "${requested}" == /* ]] || {
    log.error "Runner stage root must be an absolute path: ${requested:-unset}"
    return 1
  }
  case "${requested}" in
    "${runtime}"|"${runtime}/"*) ;;
    *)
      log.error "Runner stage root must remain inside ${runtime}: ${requested}"
      return 1
      ;;
  esac
  [[ "/${requested#/}/" != *"/../"* && "/${requested#/}/" != *"/./"* ]] || {
    log.error "Runner stage root contains an unsafe path component: ${requested}"
    return 1
  }

  mkdir -p "${requested}"
  resolved="$(cd "${requested}" && pwd -P)"
  case "${resolved}" in
    "${runtime}"|"${runtime}/"*) ;;
    *)
      log.error "Resolved runner stage root escaped ${runtime}: ${resolved}"
      return 1
      ;;
  esac
  printf '%s\n' "${resolved}"
}

runner.destination.path.is.safe() {
  local destination="${1:-}"
  local runtime=""
  local parent=""
  local resolved_parent=""
  local basename=""

  [[ -n "${RUNNER_RUNTIME_DIR:-}" && -d "${RUNNER_RUNTIME_DIR}" ]] || return 1
  [[ -n "${destination}" && "${destination}" == /* ]] || return 1
  basename="${destination##*/}"
  [[ -n "${basename}" && "${basename}" != . && "${basename}" != .. ]] || return 1
  parent="${destination%/*}"
  [[ -d "${parent}" ]] || return 1

  runtime="$(cd "${RUNNER_RUNTIME_DIR}" && pwd -P)"
  resolved_parent="$(cd "${parent}" && pwd -P)"
  case "${resolved_parent}" in
    "${runtime}"|"${runtime}/"*) ;;
    *) return 1 ;;
  esac
  [[ ! -L "${destination}" ]]
}

runner.verify.staged.file() {
  local path="${1:-}"
  [[ -f "${path}" && -r "${path}" && -s "${path}" && ! -L "${path}" ]]
}

runner.commit.staged.file() {
  local temporary="${1:-}"
  local destination="${2:-}"

  if ! chmod 0600 "${temporary}" || ! mv -f "${temporary}" "${destination}"; then
    rm -f -- "${temporary}"
    log.error "Failed to finalize staged runner file: ${destination:-unset}"
    return 1
  fi
  runner.verify.staged.file "${destination}" || {
    rm -f -- "${destination}"
    log.error "Finalized runner file failed verification: ${destination}"
    return 1
  }
}

runner.fetch.file() {
  local url="${1:-}"
  local destination="${2:-}"
  local temporary=""

  [[ "${url}" =~ ^https?://[^[:space:]]+$ ]] || {
    log.error "Runner fetch URL must be an absolute HTTP(S) URL: ${url:-unset}"
    return 1
  }
  runner.destination.path.is.safe "${destination}" || {
    log.error "Refusing unsafe runner fetch destination: ${destination:-unset}"
    return 1
  }
  command -v wget >/dev/null 2>&1 || {
    log.error "Cannot fetch runner files because wget is unavailable."
    return 1
  }

  temporary="$(mktemp "${destination}.part.XXXXXX")" || {
    log.error "Unable to allocate a temporary staged file for: ${destination}"
    return 1
  }
  log "Fetching staged file: ${url}"
  if ! wget -qO "${temporary}" "${url}" || ! runner.verify.staged.file "${temporary}"; then
    rm -f -- "${temporary}"
    log.error "Failed to fetch a non-empty staged file: ${url}"
    return 1
  fi
  runner.commit.staged.file "${temporary}" "${destination}"
}

runner.copy.file() {
  local source="${1:-}"
  local destination="${2:-}"
  local temporary=""

  runner.verify.staged.file "${source}" || {
    log.error "Local runner dependency is missing, empty, unreadable, or a symlink: ${source:-unset}"
    return 1
  }
  runner.destination.path.is.safe "${destination}" || {
    log.error "Refusing unsafe local staging destination: ${destination:-unset}"
    return 1
  }

  temporary="$(mktemp "${destination}.part.XXXXXX")" || {
    log.error "Unable to allocate a temporary local staging file for: ${destination}"
    return 1
  }
  if ! cp "${source}" "${temporary}" || ! runner.verify.staged.file "${temporary}"; then
    rm -f -- "${temporary}"
    log.error "Failed to stage local runner dependency: ${source}"
    return 1
  fi
  runner.commit.staged.file "${temporary}" "${destination}"
}

runner.verify.manifest() {
  local stage_root="${1:-}"
  local label="${2:-runner}"
  local reference=""
  shift 2 || true

  (($# > 0)) || {
    log.error "${label} manifest is empty."
    return 1
  }
  for reference in "$@"; do
    runner.relative.path.is.safe "${reference}" || {
      log.error "${label} manifest contains an unsafe reference: ${reference:-unset}"
      return 1
    }
    runner.verify.staged.file "${stage_root}/${reference}" || {
      log.error "${label} dependency failed staged verification: ${stage_root}/${reference}"
      return 1
    }
  done
}

runner.require.indexed.array() {
  local variable="${1:-}"
  local declaration=""

  [[ "${variable}" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
    log.error "Runner manifest array name is invalid: ${variable:-unset}"
    return 1
  }
  declaration="$(declare -p "${variable}" 2>/dev/null)" || {
    log.error "Required runner manifest array is not declared: ${variable}"
    return 1
  }
  [[ "${declaration}" =~ ^declare\ -[^[:space:]]*a[^[:space:]]*\ ${variable}= ]] || {
    log.error "Required runner manifest value is not an indexed array: ${variable}"
    return 1
  }
}

runner.stage.manifest() {
  local local_source_root="${1:-}"
  local published_base_url="${2:-}"
  local requested_stage_root="${3:-}"
  local label="${4:-runner}"
  local stage_root=""
  local resolved_local_root=""
  local reference=""
  local seen="|"
  shift 4 || true
  local -a references=("$@")

  ((${#references[@]} > 0)) || {
    log.error "${label} manifest is empty."
    return 1
  }
  stage_root="$(runner.prepare.stage.root "${requested_stage_root}")" || return 1

  for reference in "${references[@]}"; do
    runner.relative.path.is.safe "${reference}" || {
      log.error "${label} manifest contains an unsafe reference: ${reference:-unset}"
      return 1
    }
    [[ "${seen}" != *"|${reference}|"* ]] || {
      log.error "${label} manifest contains a duplicate reference: ${reference}"
      return 1
    }
    seen="${seen}${reference}|"
  done

  if [[ -n "${local_source_root}" ]]; then
    [[ "${local_source_root}" == /* && -d "${local_source_root}" ]] || {
      log.error "${label} local source root is unavailable: ${local_source_root}"
      return 1
    }
    resolved_local_root="$(cd "${local_source_root}" && pwd -P)"
    for reference in "${references[@]}"; do
      runner.verify.staged.file "${resolved_local_root}/${reference}" || {
        log.error "${label} local dependency is unavailable: ${resolved_local_root}/${reference}"
        return 1
      }
    done
    for reference in "${references[@]}"; do
      mkdir -p "$(dirname "${stage_root}/${reference}")"
      runner.copy.file "${resolved_local_root}/${reference}" "${stage_root}/${reference}" || return 1
    done
    RUNNER_STAGE_SOURCE=local
  else
    [[ "${published_base_url}" =~ ^https?://[^[:space:]]+$ ]] || {
      log.error "${label} published base URL is invalid: ${published_base_url:-unset}"
      return 1
    }
    for reference in "${references[@]}"; do
      mkdir -p "$(dirname "${stage_root}/${reference}")"
      runner.fetch.file "${published_base_url%/}/${reference}" "${stage_root}/${reference}" || return 1
    done
    RUNNER_STAGE_SOURCE=published
  fi

  runner.verify.manifest "${stage_root}" "${label}" "${references[@]}" || return 1
  log "Staged ${label} from ${RUNNER_STAGE_SOURCE} source (${#references[@]} files)."
}

runner.stage.ansible.feature() {
  local local_ansible_root="${1:-}"
  local published_ansible_base="${2:-}"
  local stage_root="${3:-}"
  local manifest_array=""
  local reference=""
  local -a manifest=()

  for manifest_array in \
    GROUP_VARS_FILES \
    FEATURE_PLAYBOOKS \
    RUNTIME_SUPPORT_REFS \
    FEATURE_TEMPLATE_REFS; do
    runner.require.indexed.array "${manifest_array}" || return 1
  done

  for reference in "${GROUP_VARS_FILES[@]}"; do
    manifest+=("group_vars/${reference}")
  done
  for reference in "${FEATURE_PLAYBOOKS[@]}"; do
    manifest+=("${reference}")
  done
  for reference in "${RUNTIME_SUPPORT_REFS[@]}"; do
    manifest+=("${reference}")
  done
  if ((${#FEATURE_TEMPLATE_REFS[@]} > 0)); then
    for reference in "${FEATURE_TEMPLATE_REFS[@]}"; do
      manifest+=("${reference}")
    done
  fi

  runner.stage.manifest \
    "${local_ansible_root}" \
    "${published_ansible_base}" \
    "${stage_root}" \
    "Ansible feature" \
    "${manifest[@]}"
}

runner.source.release.common() {
  local local_setup_root="${1:-}"
  local published_setup_base="${2:-}"
  local stage_root="${3:-}"
  local helper_name="${4:-release.common.sh}"

  runner.stage.manifest \
    "${local_setup_root}" \
    "${published_setup_base}" \
    "${stage_root}" \
    "shared release helper" \
    "${helper_name}" || return 1

  COMMON_HELPER_PATH="${stage_root%/}/${helper_name}"
  if ! bash -n "${COMMON_HELPER_PATH}"; then
    log.error "The staged release helper failed shell syntax validation."
    return 1
  fi
  # shellcheck disable=SC1090
  source "${COMMON_HELPER_PATH}"
}

runner.prepare.ansible.feature() {
  local local_ansible_root="${1:-}"
  local published_ansible_base="${2:-}"
  local playbook_root="${3:-}"
  local group_vars_root="${playbook_root%/}/group_vars"
  local reference=""

  runner.stage.ansible.feature \
    "${local_ansible_root}" \
    "${published_ansible_base}" \
    "${playbook_root}" || return 1

  FEATURE_GROUP_VARS_ARGS=()
  for reference in "${GROUP_VARS_FILES[@]}"; do
    runner.verify.staged.file "${group_vars_root}/${reference}" || {
      log.error "Staged group variables are unavailable: ${group_vars_root}/${reference}"
      return 1
    }
    FEATURE_GROUP_VARS_ARGS+=(-e "@${group_vars_root}/${reference}")
  done

  FEATURE_PLAYBOOK_PATHS=()
  for reference in "${FEATURE_PLAYBOOKS[@]}"; do
    runner.verify.staged.file "${playbook_root%/}/${reference}" || {
      log.error "Staged playbook is unavailable: ${playbook_root%/}/${reference}"
      return 1
    }
    FEATURE_PLAYBOOK_PATHS+=("${playbook_root%/}/${reference}")
  done
}

runner.ensure.local.ansible() {
  [[ -n "${COMMON_HELPER_PATH:-}" && -x /bin/bash ]] \
    && runner.verify.staged.file "${COMMON_HELPER_PATH}" || {
    log.error "The shared release helper must be staged before bootstrapping Ansible."
    return 1
  }
  runner.run.as.root /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TMPDIR=/tmp \
    "TMP_ROOT_DIR=${TMP_ROOT_DIR}" \
    "TMP_DIR=${TMP_DIR}" \
    "PAGES_BASE_URL=${PAGES_BASE_URL}" \
    "PYTHON_VERSION=${PYTHON_VERSION}" \
    "PYTHON_MAJOR_MINOR=${PYTHON_MAJOR_MINOR}" \
    "PYTHON_MIN_VERSION=${PYTHON_MIN_VERSION}" \
    "PYTHON_SOURCE_PREFIX=${PYTHON_SOURCE_PREFIX}" \
    "PYTHON_BIN=${PYTHON_BIN}" \
    "PYTHON_SRC_DIR=${PYTHON_SRC_DIR}" \
    "PYTHON_SRC_ARCHIVE=${PYTHON_SRC_ARCHIVE}" \
    "PYTHON_SRC_URL=${PYTHON_SRC_URL}" \
    "CONTROLLER_PYTHON_POLICY=${CONTROLLER_PYTHON_POLICY}" \
    "SYSTEM_PYTHON_BIN=${SYSTEM_PYTHON_BIN}" \
    "ANSIBLE_VENV=${ANSIBLE_VENV}" \
    "ANSIBLE_VENV_BIN=${ANSIBLE_VENV_BIN}" \
    "ANSIBLE_CORE_VERSION=${ANSIBLE_CORE_VERSION}" \
    "ANSIBLE_CORE_SPEC=${ANSIBLE_CORE_SPEC}" \
    "MANAGED_TARGET_PYTHON_HOME=${MANAGED_TARGET_PYTHON_HOME}" \
    "MANAGED_TARGET_PYTHON_PATH=${MANAGED_TARGET_PYTHON_PATH}" \
    "MANAGED_TARGET_HANDOFF_MARKER=${MANAGED_TARGET_HANDOFF_MARKER}" \
    /bin/bash "${COMMON_HELPER_PATH}" ensure-local-ansible
}

runner.run.ansible.playbooks() {
  local extra_vars_path="${1:-}"
  shift || true
  local -a playbooks=("$@")
  local playbook=""

  runner.verify.staged.file "${extra_vars_path}" || {
    log.error "Feature extra-vars file is unavailable: ${extra_vars_path:-unset}"
    return 1
  }
  ((${#playbooks[@]} > 0)) || {
    log.error "No Ansible playbook was supplied."
    return 64
  }
  for playbook in "${playbooks[@]}"; do
    runner.verify.staged.file "${playbook}" || {
      log.error "Staged playbook is unavailable: ${playbook:-unset}"
      return 1
    }
  done
  runner.run.as.root /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TMPDIR=/tmp \
    "${ANSIBLE_VENV_BIN}" \
      -i localhost, \
      -c local \
      "${FEATURE_GROUP_VARS_ARGS[@]}" \
      -e "@${extra_vars_path}" \
      "${playbooks[@]}"
}

runner.report.command() {
  local report_path="${1:-}"
  local label="${2:-command}"
  shift 2 || true

  {
    printf '\n## %s\n' "${label}"
    if (($# == 0)); then
      printf 'unavailable: no command supplied\n'
    elif [[ "$1" == */* && ! -x "$1" ]]; then
      printf 'unavailable: %s\n' "$1"
    elif [[ "$1" != */* ]] && ! command -v "$1" >/dev/null 2>&1; then
      printf 'unavailable: %s\n' "$1"
    else
      "$@" 2>&1 || true
    fi
  } | tee -a "${report_path}"
}

runner.report.text() {
  local report_path="${1:-}"
  local label="${2:-file}"
  local path="${3:-}"

  {
    printf '\n## %s\n' "${label}"
    if [[ -r "${path}" ]]; then
      sed -n '1,240p' "${path}"
    else
      printf 'unavailable: %s\n' "${path:-unset}"
    fi
  } | tee -a "${report_path}"
}

runner.authenticate.sudo() {
  if [[ "$(runner.euid)" -eq 0 ]]; then
    RUNNER_SUDO_AUTHENTICATED=1
    return 0
  fi
  if [[ "${RUNNER_SUDO_AUTHENTICATED}" == 1 ]] && sudo -n -- true >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log.error "Managed mode requires root privileges, but sudo is unavailable."
    return 1
  fi
  if sudo -n -- true >/dev/null 2>&1; then
    RUNNER_SUDO_AUTHENTICATED=1
    return 0
  fi
  if ! runner.have.controlling.tty; then
    log.error "Root privileges are required, but sudo needs authentication and no usable /dev/tty is available."
    log.error "Run from an interactive terminal, use ssh -t, configure passwordless sudo, or start this runner with sudo."
    return 1
  fi

  log "Root privileges required; requesting sudo once through /dev/tty."
  log "Password input is not echoed."
  if ! sudo -v <"${RUNNER_TTY_PATH}"; then
    log.error "sudo authentication failed or was cancelled."
    return 1
  fi
  if ! sudo -n -- true >/dev/null 2>&1; then
    log.error "sudo authentication completed, but a noninteractive privileged session was not established."
    return 1
  fi
  RUNNER_SUDO_AUTHENTICATED=1
}

runner.ensure.privileged.session() {
  runner.authenticate.sudo
}

runner.run.as.root() {
  (($# > 0)) || {
    log.error "runner.run.as.root requires a command."
    return 64
  }
  if [[ "$(runner.euid)" -eq 0 ]]; then
    "$@" </dev/null
    return
  fi
  if [[ "${RUNNER_SUDO_AUTHENTICATED}" != 1 ]]; then
    runner.ensure.privileged.session || return 1
  fi
  sudo -n -- "$@" </dev/null
}

runner.cleanup.runtime() {
  local runtime="${RUNNER_RUNTIME_DIR:-}"
  local feature="${RUNNER_RUNTIME_FEATURE:-}"

  [[ "${RUNNER_RUNTIME_ACTIVE:-0}" == 1 ]] || return 0
  RUNNER_RUNTIME_ACTIVE=0
  RUNNER_RUNTIME_DIR=""

  if ! runner.runtime.path.is.safe "${feature}" "${runtime}"; then
    log.warn "Refusing cleanup of an unsafe runner runtime path: ${runtime:-unset}"
    return 1
  fi
  if rm -rf -- "${runtime}" 2>/dev/null; then
    return 0
  fi
  if [[ "$(runner.euid)" -ne 0 ]] && sudo -n -- true >/dev/null 2>&1; then
    sudo -n -- rm -rf -- "${runtime}" || {
      log.warn "Privileged cleanup failed for runner runtime: ${runtime}"
      return 1
    }
    return 0
  fi

  log.warn "Runner runtime could not be removed automatically: ${runtime}"
  return 1
}
