#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh
## Thin Debian kiosk orchestrator.
## Local usage:
##   ./setup/cli/kiosk.app.sh [preflight|apply|disable]
## Published usage:
##   wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh | bash
##
## Kiosk orchestration order (apply mode) by default:
##   1) x11 feature
##   2) startx feature
##   3) openbox feature
##   4) touchscreen feature
##   5) autologin feature
##
## Typical profiles:
##   DEBIAN_AUTOAPP_PROFILE=command
##     - sets default command to nano (debug/dev session)
##     - does not force local X startup
##   DEBIAN_AUTOAPP_PROFILE=startx
##     - sets default command to the managed STARTX wrapper path
##     - enables local X startup by default

set -euo pipefail

log() { printf '[setup.cli.kiosk.app] %s\n' "$*" >&2; }
log.error() { printf '[setup.cli.kiosk.app][error] %s\n' "$*" >&2; }

PAGES_BASE_URL="${PAGES_BASE_URL:-https://devs-guide.github.io/debian}"
AUTOAPP_SELF_URL="${DEBIAN_AUTOAPP_SELF_URL:-${PAGES_BASE_URL}/setup/cli/kiosk.app.sh}"
AUTOAPP_DEFAULT_STARTX_COMMAND="${DEBIAN_AUTOAPP_STARTX_DEFAULT_COMMAND:-/usr/local/bin/kiosk-startx}"
FEATURE_MODE="${1:-${DEBIAN_AUTOAPP_MODE:-apply}}"
AUTOAPP_ENABLE="${DEBIAN_AUTOAPP_ENABLE:-}"
AUTOAPP_USER="${DEBIAN_AUTOAPP_USER:-app}"
AUTOAPP_TTY="${DEBIAN_AUTOAPP_TTY:-tty1}"
AUTOAPP_TERM="${DEBIAN_AUTOAPP_TERM:-linux}"
AUTOAPP_NORESET="${DEBIAN_AUTOAPP_NORESET:-1}"
AUTOAPP_NOCLEAR="${DEBIAN_AUTOAPP_NOCLEAR:-1}"
AUTOAPP_PROFILE="${DEBIAN_AUTOAPP_PROFILE:-command}"
AUTOAPP_COMMAND="${DEBIAN_AUTOAPP_COMMAND:-}"
AUTOAPP_MARKER_ENABLE="${DEBIAN_AUTOAPP_MARKER_ENABLE:-1}"
AUTOAPP_MARKER_PATH="${DEBIAN_AUTOAPP_MARKER_PATH:-/home/${AUTOAPP_USER}/.cache/autologin-${AUTOAPP_TTY}.ok}"
AUTOAPP_RUNTIME_FACTS_PATH="${DEBIAN_AUTOAPP_RUNTIME_FACTS_PATH:-/etc/ansible/debian/facts/autologin.yml}"
AUTOAPP_SUDO_REEXEC="${DEBIAN_AUTOAPP_SUDO_REEXEC:-0}"
AUTOAPP_RUN_X11="${DEBIAN_AUTOAPP_RUN_X11:-}"
AUTOAPP_RUN_STARTX="${DEBIAN_AUTOAPP_RUN_STARTX:-}"
AUTOAPP_RUN_OPENBOX="${DEBIAN_AUTOAPP_RUN_OPENBOX:-}"
AUTOAPP_RUN_TOUCHSCREEN="${DEBIAN_AUTOAPP_RUN_TOUCHSCREEN:-}"

AUTOAPP_RUN_X11_SET=0
AUTOAPP_RUN_STARTX_SET=0
AUTOAPP_RUN_OPENBOX_SET=0
AUTOAPP_RUN_TOUCHSCREEN_SET=0
[[ -n "${DEBIAN_AUTOAPP_RUN_X11+x}" ]] && AUTOAPP_RUN_X11_SET=1
[[ -n "${DEBIAN_AUTOAPP_RUN_STARTX+x}" ]] && AUTOAPP_RUN_STARTX_SET=1
[[ -n "${DEBIAN_AUTOAPP_RUN_OPENBOX+x}" ]] && AUTOAPP_RUN_OPENBOX_SET=1
[[ -n "${DEBIAN_AUTOAPP_RUN_TOUCHSCREEN+x}" ]] && AUTOAPP_RUN_TOUCHSCREEN_SET=1
AUTOAPP_RUNNER_PREFIX="${AUTOAPP_RUNNER_PREFIX:-${PAGES_BASE_URL}/setup/cli}"
FEATURE_PLAYBOOKS=(
  "cli/x11.yml"
  "cli/startx.yml"
  "cli/openbox.yml"
  "cli/touchscreen.yml"
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

collect.sudo.env.args() {
  local -n _out="$1"

  _out=(
    "DEBIAN_AUTOAPP_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_AUTOAPP_MODE=${FEATURE_MODE}"
    "DEBIAN_AUTOAPP_USER=${AUTOAPP_USER}"
    "DEBIAN_AUTOAPP_TTY=${AUTOAPP_TTY}"
    "DEBIAN_AUTOAPP_TERM=${AUTOAPP_TERM}"
    "DEBIAN_AUTOAPP_NORESET=${AUTOAPP_NORESET}"
    "DEBIAN_AUTOAPP_NOCLEAR=${AUTOAPP_NOCLEAR}"
    "DEBIAN_AUTOAPP_PROFILE=${AUTOAPP_PROFILE}"
    "DEBIAN_AUTOAPP_COMMAND=${AUTOAPP_COMMAND}"
    "DEBIAN_AUTOAPP_MARKER_ENABLE=${AUTOAPP_MARKER_ENABLE}"
    "DEBIAN_AUTOAPP_MARKER_PATH=${AUTOAPP_MARKER_PATH}"
    "DEBIAN_AUTOAPP_RUNTIME_FACTS_PATH=${AUTOAPP_RUNTIME_FACTS_PATH}"
    "DEBIAN_AUTOAPP_SELF_URL=${AUTOAPP_SELF_URL}"
    "DEBIAN_AUTOAPP_SUDO_REEXEC=1"
  )
}

current.script.path() {
  local source_path="${BASH_SOURCE[0]:-}"

  case "${source_path}" in
    ""|-|/dev/fd/*|/proc/self/fd/*)
      return 1
      ;;
  esac

  if [[ -r "${source_path}" ]]; then
    readlink -f "${source_path}" 2>/dev/null || printf '%s\n' "${source_path}"
    return 0
  fi

  return 1
}

ensure.root.or.sudo.reexec() {
  local script_path=""
  local -a sudo_env

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${AUTOAPP_SUDO_REEXEC}" = "1" ]]; then
    log.error "sudo re-entry was requested but the script is still not running as root."
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    log.error "This setup requires root privileges. Install sudo or run as root."
    exit 1
  fi

  log "Root privileges required; requesting sudo..."
  if ! sudo -v; then
    log.error "sudo authentication failed or was cancelled."
    exit 1
  fi

  collect.sudo.env.args sudo_env
  if script_path="$(current.script.path)"; then
    exec sudo -E env "${sudo_env[@]}" bash "${script_path}" "$@"
  fi

  if command -v wget >/dev/null 2>&1; then
    exec sudo -E env "${sudo_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${AUTOAPP_SELF_URL}" "$@"
  fi

  log.error "Cannot re-enter with sudo from stdin because wget is unavailable."
  exit 1
}

reject.root.display.commands() {
  local command_text="${1:-}"

  if printf '%s' "${command_text}" | grep -Eq '(^|[[:space:]])(sudo[[:space:]]+)?startx([[:space:]]|$)'; then
    log.error "Auto-app command profile refuses direct startx execution."
    log.error "Use DEBIAN_AUTOAPP_PROFILE=startx to run the managed STARTX wrapper."
    return 1
  fi

  if printf '%s' "${command_text}" | grep -Eq '(^|[[:space:]])--[[:space:]]*:[0-9]+'; then
    log.error "Auto-app command profile refuses explicit root-owned DISPLAY server startup patterns."
    log.error "Use DEBIAN_AUTOAPP_PROFILE=startx to launch X from tty1 as app."
    return 1
  fi

  return 0
}

resolve.autoapp.profile() {
  AUTOAPP_PROFILE="${AUTOAPP_PROFILE,,}"

  case "${AUTOAPP_PROFILE}" in
    command)
      if [[ -z "${AUTOAPP_COMMAND}" ]]; then
        AUTOAPP_COMMAND="nano"
      fi

      if [[ "${AUTOAPP_COMMAND}" != "${AUTOAPP_DEFAULT_STARTX_COMMAND}" ]] && ! reject.root.display.commands "${AUTOAPP_COMMAND}"; then
        exit 1
      fi
      ;;
    startx)
      if [[ -z "${AUTOAPP_COMMAND}" ]]; then
        AUTOAPP_COMMAND="${AUTOAPP_DEFAULT_STARTX_COMMAND}"
      fi
      ;;
    *)
      log.error "Unsupported DEBIAN_AUTOAPP_PROFILE=${AUTOAPP_PROFILE}. Use command or startx."
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

run.autologin.env.args() {
  local -n _out="$1"

  _out=(
    "DEBIAN_AUTOLOGIN_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_AUTOLOGIN_MODE=${FEATURE_MODE}"
    "DEBIAN_AUTOLOGIN_USER=${AUTOAPP_USER}"
    "DEBIAN_AUTOLOGIN_TTY=${AUTOAPP_TTY}"
    "DEBIAN_AUTOLOGIN_TERM=${AUTOAPP_TERM}"
    "DEBIAN_AUTOLOGIN_NORESET=${AUTOAPP_NORESET}"
    "DEBIAN_AUTOLOGIN_NOCLEAR=${AUTOAPP_NOCLEAR}"
    "DEBIAN_AUTOLOGIN_ACTION=command"
    "DEBIAN_AUTOLOGIN_COMMAND=${AUTOAPP_COMMAND}"
    "DEBIAN_AUTOLOGIN_VALIDATION_BANNER=0"
    "DEBIAN_AUTOLOGIN_MARKER_ENABLE=${AUTOAPP_MARKER_ENABLE}"
    "DEBIAN_AUTOLOGIN_MARKER_PATH=${AUTOAPP_MARKER_PATH}"
    "DEBIAN_AUTOLOGIN_RUNTIME_FACTS_PATH=${AUTOAPP_RUNTIME_FACTS_PATH}"
  )
}

collect.x11.env.args() {
  local -n _out="$1"
  _out=(
    "DEBIAN_X11_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_X11_MODE=${FEATURE_MODE}"
    "DEBIAN_X11_INSTALL_PACKAGES=1"
    "DEBIAN_X11_SUDO_REEXEC=1"
  )
}

collect.startx.env.args() {
  local -n _out="$1"
  _out=(
    "DEBIAN_STARTX_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_STARTX_MODE=${FEATURE_MODE}"
    "DEBIAN_STARTX_USER=${AUTOAPP_USER}"
    "DEBIAN_STARTX_TTY=${AUTOAPP_TTY}"
    "DEBIAN_STARTX_DISPLAY=:0"
    "DEBIAN_STARTX_INSTALL_PACKAGES=0"
    "DEBIAN_STARTX_MANAGE_XWRAPPER=1"
    "DEBIAN_STARTX_ALLOWED_USERS=console"
    "DEBIAN_STARTX_NEEDS_ROOT_RIGHTS=auto"
    "DEBIAN_STARTX_MANAGE_XINITRC=1"
    "DEBIAN_STARTX_MANAGE_WRAPPER=1"
    "DEBIAN_STARTX_WRAPPER_PATH=/usr/local/bin/kiosk-startx"
    "DEBIAN_STARTX_XINITRC_PATH=/home/${AUTOAPP_USER}/.xinitrc"
    "DEBIAN_STARTX_XSESSION_HOOK_DIR=/home/${AUTOAPP_USER}/.config/debian/xsession.d"
    "DEBIAN_STARTX_OPENBOX_COMMAND=/usr/bin/openbox-session"
    "DEBIAN_STARTX_SERVER_ARGS=-nolisten tcp"
    "DEBIAN_STARTX_SUDO_REEXEC=1"
  )
}

collect.openbox.env.args() {
  local -n _out="$1"
  _out=(
    "DEBIAN_OPENBOX_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_OPENBOX_MODE=${FEATURE_MODE}"
    "DEBIAN_OPENBOX_USER=${AUTOAPP_USER}"
    "DEBIAN_OPENBOX_SESSION_COMMAND=/usr/bin/openbox-session"
    "DEBIAN_OPENBOX_XINITRC_PATH=/home/${AUTOAPP_USER}/.xinitrc"
    "DEBIAN_OPENBOX_XSESSION_HOOK_DIR=/home/${AUTOAPP_USER}/.config/debian/xsession.d"
    "DEBIAN_OPENBOX_MANAGE_XINITRC=1"
    "DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR=1"
    "DEBIAN_OPENBOX_FULLSCREEN=0"
    "DEBIAN_OPENBOX_FULLSCREEN_MATCH=xclock"
    "DEBIAN_OPENBOX_FULLSCREEN_RETRIES=24"
    "DEBIAN_OPENBOX_FULLSCREEN_DELAY_MS=250"
    "DEBIAN_OPENBOX_FULLSCREEN_HELPER=/usr/local/bin/debian-openbox-fullscreen"
    "DEBIAN_OPENBOX_SUDO_REEXEC=1"
  )
}

collect.touchscreen.env.args() {
  local -n _out="$1"
  _out=(
    "DEBIAN_TOUCHSCREEN_ENABLE=${AUTOAPP_ENABLE}"
    "DEBIAN_TOUCHSCREEN_MODE=${FEATURE_MODE}"
    "DEBIAN_TOUCHSCREEN_USER=${AUTOAPP_USER}"
    "DEBIAN_TOUCHSCREEN_MATCH=eGalax|D-WAV|Titan6001|TouchController|Touchscreen"
    "DEBIAN_TOUCHSCREEN_RUNTIME_FACTS_PATH=/etc/ansible/debian/facts/touchscreen.yml"
    "DEBIAN_TOUCHSCREEN_INSTALL_PACKAGES=1"
    "DEBIAN_TOUCHSCREEN_INSTALL_EVTEST=0"
    "DEBIAN_TOUCHSCREEN_SUDO_REEXEC=1"
  )
}

run.local.feature() {
  local runner="$1"
  local feature="$2"
  local collect_fn="$3"
  local -a feature_env

  if [[ ! -r "${runner}" ]]; then
    return 1
  fi

  "${collect_fn}" feature_env
  log "Using local runner: ${runner}"
  env "${feature_env[@]}" bash "${runner}" "${FEATURE_MODE}"
}

run.remote.feature() {
  local feature="$1"
  local collect_fn="$2"
  local url="${AUTOAPP_RUNNER_PREFIX}/${feature}.sh"
  local -a feature_env

  "${collect_fn}" feature_env
  log "Using published runner: ${url}"
  if ! command -v wget >/dev/null 2>&1; then
    log.error "wget is required for remote feature bootstrap."
    return 1
  fi
  env "${feature_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${url}" "${FEATURE_MODE}"
}

run.feature() {
  local feature="$1"
  local local_runner="$2"
  local collect_fn="$3"

  if run.local.feature "${local_runner}" "${feature}" "${collect_fn}"; then
    return 0
  fi
  run.remote.feature "${feature}" "${collect_fn}"
}

run.kiosk.features() {
  local script_dir runner_script

  if is.true "${AUTOAPP_RUN_X11}"; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    run.feature "x11" "${script_dir}/x11.sh" collect.x11
  else
    log "Skipping x11 feature (DEBIAN_AUTOAPP_RUN_X11=${AUTOAPP_RUN_X11})"
  fi

  if is.true "${AUTOAPP_RUN_STARTX}"; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    run.feature "startx" "${script_dir}/startx.sh" collect.startx
  else
    log "Skipping startx feature (DEBIAN_AUTOAPP_RUN_STARTX=${AUTOAPP_RUN_STARTX})"
  fi

  if is.true "${AUTOAPP_RUN_OPENBOX}"; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    run.feature "openbox" "${script_dir}/openbox.sh" collect.openbox
  else
    log "Skipping openbox feature (DEBIAN_AUTOAPP_RUN_OPENBOX=${AUTOAPP_RUN_OPENBOX})"
  fi

  if is.true "${AUTOAPP_RUN_TOUCHSCREEN}"; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    run.feature "touchscreen" "${script_dir}/touchscreen.sh" collect.touchscreen
  else
    log "Skipping touchscreen feature (DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=${AUTOAPP_RUN_TOUCHSCREEN})"
  fi
}

run.autologin() {
  local script_dir="$1"
  local -a autologin_env

  run.autologin.env.args autologin_env
  if [[ -r "${script_dir}/../autologin.sh" ]]; then
    local runner="${script_dir}/../autologin.sh"
    log "Using local runner: ${runner}"
    env "${autologin_env[@]}" bash "${runner}" "${FEATURE_MODE}"
    return 0
  fi

  log "Using published runner: ${PAGES_BASE_URL}/setup/autologin.sh"
  env "${autologin_env[@]}" bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${PAGES_BASE_URL}/setup/autologin.sh" "${FEATURE_MODE}"
}

resolve.run.flags() {
  if [[ "${AUTOAPP_RUN_X11_SET}" -eq 0 ]]; then
    AUTOAPP_RUN_X11=1
  fi

  if [[ "${AUTOAPP_RUN_STARTX_SET}" -eq 0 ]]; then
    if [[ "${AUTOAPP_PROFILE}" == "startx" ]]; then
      AUTOAPP_RUN_STARTX=1
    else
      AUTOAPP_RUN_STARTX=0
    fi
  fi

  if [[ "${AUTOAPP_RUN_OPENBOX_SET}" -eq 0 ]]; then
    AUTOAPP_RUN_OPENBOX=1
  fi

  if [[ "${AUTOAPP_RUN_TOUCHSCREEN_SET}" -eq 0 ]]; then
    AUTOAPP_RUN_TOUCHSCREEN=0
  fi
}

normalize.autoapp.flag() {
  local value="${1:-}"
  if is.true "${value}"; then
    printf '1'
  else
    printf '0'
  fi
}

normalize.feature.flags() {
  AUTOAPP_RUN_X11="$(normalize.autoapp.flag "${AUTOAPP_RUN_X11}")"
  AUTOAPP_RUN_STARTX="$(normalize.autoapp.flag "${AUTOAPP_RUN_STARTX}")"
  AUTOAPP_RUN_OPENBOX="$(normalize.autoapp.flag "${AUTOAPP_RUN_OPENBOX}")"
  AUTOAPP_RUN_TOUCHSCREEN="$(normalize.autoapp.flag "${AUTOAPP_RUN_TOUCHSCREEN}")"
}

main() {
  local script_dir local_runner

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local_runner="$(cd "${script_dir}/.." && pwd)/autologin.sh"

  require.valid.mode
  resolve.autoapp.profile
  resolve.defaults
  resolve.run.flags
  normalize.feature.flags
  ensure.root.or.sudo.reexec "$@"

  log "Mode: ${FEATURE_MODE}"
  log "Auto-app enabled: ${AUTOAPP_ENABLE}"
  log "User: ${AUTOAPP_USER}"
  log "TTY: ${AUTOAPP_TTY}"
  log "Profile: ${AUTOAPP_PROFILE}"
  log "First app command: ${AUTOAPP_COMMAND}"
  log "Feature plan: x11=${AUTOAPP_RUN_X11} startx=${AUTOAPP_RUN_STARTX} openbox=${AUTOAPP_RUN_OPENBOX} touchscreen=${AUTOAPP_RUN_TOUCHSCREEN}"

  run.kiosk.features
  run.autologin "${script_dir}"
}

main "$@"
