#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_DIR="${DIR_PUBLISH:-${PUBLISH_DIR:-${ROOT}/static}}"

log() {
  printf '[www.pages] %s\n' "$*" >&2
}

copy_file() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "${dest}")"
  cp "${src}" "${dest}"
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    log "missing required file: ${path}"
    exit 1
  fi
}

main() {
  local src dest
  local -a root_files=(
    "www/index.html:index.html"
    "setup/bootstrap.sh:setup/bootstrap.sh"
    "setup/debian.sh:setup/debian.sh"
    "setup/metal.sh:setup/metal.sh"
    "setup/hardware.sh:setup/hardware.sh"
    "setup/hardware.sh:setup/hardware"
    "setup/release.common.sh:setup/release.common.sh"
    "setup/cli/node.sh:setup/cli/node.sh"
    "setup/cli/node.sh:setup/cli/node"
    "setup/cli/codex.sh:setup/cli/codex.sh"
    "setup/cli/tauri.sh:setup/cli/tauri.sh"
    "setup/cli/tauri.sh:setup/cli/tauri"
    "readme.md:readme.md"
  )

  require_file "${ROOT}/www/index.html"
  require_file "${ROOT}/setup/bootstrap.sh"
  require_file "${ROOT}/setup/debian.sh"
  require_file "${ROOT}/setup/metal.sh"
  require_file "${ROOT}/setup/hardware.sh"
  require_file "${ROOT}/setup/release.common.sh"
  require_file "${ROOT}/setup/cli/node.sh"
  require_file "${ROOT}/setup/cli/codex.sh"
  require_file "${ROOT}/setup/cli/tauri.sh"
  require_file "${ROOT}/ansible/install.playbooks.txt"

  rm -rf "${PUBLISH_DIR}"
  mkdir -p "${PUBLISH_DIR}"

  for entry in "${root_files[@]}"; do
    src="${ROOT}/${entry%%:*}"
    dest="${PUBLISH_DIR}/${entry#*:}"
    log "publish ${entry%%:*} -> ${entry#*:}"
    copy_file "${src}" "${dest}"
  done

  cp -R "${ROOT}/ansible" "${PUBLISH_DIR}/"

  if [[ -d "${ROOT}/docs" ]]; then
    cp -R "${ROOT}/docs" "${PUBLISH_DIR}/"
  fi

  log "published static tree at ${PUBLISH_DIR}"
}

main "$@"
