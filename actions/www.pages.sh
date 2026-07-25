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
    "setup/bootstrap.sh:setup/bootstrap.sh"
    "setup/debian.sh:setup/debian.sh"
    "setup/metal.sh:setup/metal.sh"
    "setup/hardware.sh:setup/hardware.sh"
    "setup/autologin.sh:setup/autologin.sh"
    "setup/runner.common.sh:setup/runner.common.sh"
    "setup/release.common.sh:setup/release.common.sh"
    "setup/cli/node.sh:setup/cli/node.sh"
    "setup/cli/kiosk.app.sh:setup/cli/kiosk.app.sh"
    "setup/cli/x11.sh:setup/cli/x11.sh"
    "setup/cli/openbox.sh:setup/cli/openbox.sh"
    "setup/cli/touchscreen.sh:setup/cli/touchscreen.sh"
    "setup/cli/codex.sh:setup/cli/codex.sh"
    "setup/cli/startx.sh:setup/cli/startx.sh"
    "setup/cli/tauri.sh:setup/cli/tauri.sh"
    "setup/cli/nvidia.sh:setup/cli/nvidia.sh"
    "setup/cli/nvlink.sh:setup/cli/nvlink.sh"
    "readme.md:readme.md"
  )

  require_file "${ROOT}/actions/build.docs.sh"
  require_file "${ROOT}/docs/readme.md"
  require_file "${ROOT}/docs/_templates/page.html"
  require_file "${ROOT}/docs/_assets/site.css"
  require_file "${ROOT}/setup/bootstrap.sh"
  require_file "${ROOT}/setup/debian.sh"
  require_file "${ROOT}/setup/metal.sh"
  require_file "${ROOT}/setup/hardware.sh"
  require_file "${ROOT}/setup/autologin.sh"
  require_file "${ROOT}/setup/runner.common.sh"
  require_file "${ROOT}/setup/release.common.sh"
  require_file "${ROOT}/setup/cli/node.sh"
  require_file "${ROOT}/setup/cli/kiosk.app.sh"
  require_file "${ROOT}/setup/cli/x11.sh"
  require_file "${ROOT}/setup/cli/openbox.sh"
  require_file "${ROOT}/setup/cli/touchscreen.sh"
  require_file "${ROOT}/setup/cli/codex.sh"
  require_file "${ROOT}/setup/cli/startx.sh"
  require_file "${ROOT}/setup/cli/tauri.sh"
  require_file "${ROOT}/setup/cli/nvidia.sh"
  require_file "${ROOT}/ansible/cli/nvidia.yml"
  require_file "${ROOT}/ansible/tasks/nvidia.normalize-observations.yml"
  require_file "${ROOT}/setup/cli/nvlink.sh"
  require_file "${ROOT}/ansible/cli/nvlink.yml"
  require_file "${ROOT}/ansible/files/nvlink/nvidia-cuda-smoke.cu"
  require_file "${ROOT}/ansible/files/nvlink/nvidia-p2p-verify.cu"
  require_file "${ROOT}/ansible/files/nvlink/nvidia-topology-parser.py"
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

  DOCS_SITE_ROOT="${DOCS_SITE_ROOT:-/debian}" \
    bash "${ROOT}/actions/build.docs.sh" \
      --source "${ROOT}/docs" \
      --output "${PUBLISH_DIR}"

  log "published static tree at ${PUBLISH_DIR}"
}

main "$@"
