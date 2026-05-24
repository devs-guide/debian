#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/auto.app.sh
## Minimal Debian auto-app runner.
## Local usage:
##   ./setup/cli/auto.app.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/auto.app | bash
##
## This wrapper configures tty autologin + first-app launch by calling
## setup/autologin.sh with autologin_action=command.
##
## Default app command is "nano". Override with:
##   DEBIAN_AUTOAPP_COMMAND='your command


set -euo pipefail

log() { printf '[setup.cli.auto.app] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.auto.app][error] %s\n' "$*" >&2; }

PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
FEATURE_MODE="${1:-${DEBIAN_AUTOAPP_MODE:-apply}}"
AUTOAPP_ENABLE="${DEBIAN_AUTOAPP_ENABLE:-}"
AUTOAPP_USER="${DEBIAN_AUTOAPP_USER:-app}"
AUTOAPP_TTY="${DEBIAN_AUTOAPP_TTY:-tty1}"
AUTOAPP_TERM="${DEBIAN_AUTOAPP_TERM:-linux}"
AUTOAPP_NORESET="${DEBIAN_AUTOAPP_NORESET:-1}"
AUTOAPP_NOCLEAR="${DEBIAN_AUTOAPP_NOCLEAR:-1}"
AUTOAPP_COMMAND="${DEBIAN_AUTOAPP_COMMAND:-nano}"
AUTOAPP_MARKER_ENABLE="${DEBIAN_AUTOAPP_MARKER_ENABLE:-1}"
AUTOAPP_MARKER_PATH="${DEBIAN_AUTOAPP_MARKER_PATH:-/home/${AUTOAPP_USER}/.cache/autologin-${AUTOAPP_TTY}.ok}"
AUTOAPP_RUNTIME_FACTS_PATH="${DEBIAN_AUTOAPP_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/autologin.yml}"
FEATURE_PLAYBOOKS=(
  "autologin.yml"
)

is.true() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

require.valid.mode() {
  case "${FEATURE_MODE}" in
    preflight|apply|disable) ;;
    *)
      log.error "Unsupported mode: ${FEATURE_MODE}"
      log.error "Use one of: preflight, apply, disable"
      exit 1
      ;;
  esac
}

resolve.defaults() {
  if [[ -z "${AUTOAPP_ENABLE}" ]]; then
    case "${FEATURE_MODE}" in
      disable) AUTOAPP_ENABLE=0 ;;
      *) AUTOAPP_ENABLE=1 ;;
    esac
  fi
}

run.local.autologin() {
  local runner="$1"
  shift
  exec env \
    DEBIAN_AUTOLOGIN_ENABLE="${AUTOAPP_ENABLE}" \
    DEBIAN_AUTOLOGIN_MODE="${FEATURE_MODE}" \
    DEBIAN_AUTOLOGIN_USER="${AUTOAPP_USER}" \
    DEBIAN_AUTOLOGIN_TTY="${AUTOAPP_TTY}" \
    DEBIAN_AUTOLOGIN_TERM="${AUTOAPP_TERM}" \
    DEBIAN_AUTOLOGIN_NORESET="${AUTOAPP_NORESET}" \
    DEBIAN_AUTOLOGIN_NOCLEAR="${AUTOAPP_NOCLEAR}" \
    DEBIAN_AUTOLOGIN_ACTION="command" \
    DEBIAN_AUTOLOGIN_COMMAND="${AUTOAPP_COMMAND}" \
    DEBIAN_AUTOLOGIN_VALIDATION_BANNER=0 \
    DEBIAN_AUTOLOGIN_MARKER_ENABLE="${AUTOAPP_MARKER_ENABLE}" \
    DEBIAN_AUTOLOGIN_MARKER_PATH="${AUTOAPP_MARKER_PATH}" \
    DEBIAN_AUTOLOGIN_RUNTIME_FACTS_PATH="${AUTOAPP_RUNTIME_FACTS_PATH}" \
    bash "${runner}" "${FEATURE_MODE}" "$@"
}

run.remote.autologin() {
  local url="${PAGES_BASE_URL}/setup/autologin"
  exec wget -qO- "${url}" | env \
    DEBIAN_AUTOLOGIN_ENABLE="${AUTOAPP_ENABLE}" \
    DEBIAN_AUTOLOGIN_MODE="${FEATURE_MODE}" \
    DEBIAN_AUTOLOGIN_USER="${AUTOAPP_USER}" \
    DEBIAN_AUTOLOGIN_TTY="${AUTOAPP_TTY}" \
    DEBIAN_AUTOLOGIN_TERM="${AUTOAPP_TERM}" \
    DEBIAN_AUTOLOGIN_NORESET="${AUTOAPP_NORESET}" \
    DEBIAN_AUTOLOGIN_NOCLEAR="${AUTOAPP_NOCLEAR}" \
    DEBIAN_AUTOLOGIN_ACTION="command" \
    DEBIAN_AUTOLOGIN_COMMAND="${AUTOAPP_COMMAND}" \
    DEBIAN_AUTOLOGIN_VALIDATION_BANNER=0 \
    DEBIAN_AUTOLOGIN_MARKER_ENABLE="${AUTOAPP_MARKER_ENABLE}" \
    DEBIAN_AUTOLOGIN_MARKER_PATH="${AUTOAPP_MARKER_PATH}" \
    DEBIAN_AUTOLOGIN_RUNTIME_FACTS_PATH="${AUTOAPP_RUNTIME_FACTS_PATH}" \
    bash
}

main() {
  local script_dir local_runner
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local_runner="$(cd "${script_dir}/.." && pwd)/autologin.sh"

  require.valid.mode
  resolve.defaults

  log "Mode: ${FEATURE_MODE}"
  log "Enable autologin: ${AUTOAPP_ENABLE}"
  log "User: ${AUTOAPP_USER}"
  log "TTY: ${AUTOAPP_TTY}"
  log "First app command: ${AUTOAPP_COMMAND}"

  if [[ -r "${local_runner}" ]]; then
    log "Using local runner: ${local_runner}"
    run.local.autologin "${local_runner}"
  fi

  log "Using published runner: ${PAGES_BASE_URL}/setup/autologin"
  run.remote.autologin
}

main "$@"
