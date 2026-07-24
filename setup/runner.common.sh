#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/runner.common.sh
# Shared privilege and per-run staging contract for setup entrypoints.

set -euo pipefail

: "${RUNNER_RUNTIME_DIR:=}"
: "${RUNNER_RUNTIME_FEATURE:=}"
: "${RUNNER_RUNTIME_ACTIVE:=0}"
: "${RUNNER_SUDO_AUTHENTICATED:=0}"
: "${RUNNER_TTY_PATH:=/dev/tty}"

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
