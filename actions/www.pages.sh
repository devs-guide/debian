#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISH_DIR_REQUESTED="${DIR_PUBLISH:-${PUBLISH_DIR:-${ROOT}/static}}"
PUBLISH_DIR=""
PUBLICATION_MANIFEST="${ROOT}/actions/publication.manifest"
PUBLICATION_LABEL="www.pages"

# shellcheck source=actions/lib/publication.sh
source "${ROOT}/actions/lib/publication.sh"

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

publish.manifest.entry() {
  local kind="$1"
  local source="$2"
  local destination="$3"
  local source_path="${ROOT}/${source}"
  local destination_path="${PUBLISH_DIR}/${destination}"

  log "publish ${source} -> ${destination}"
  case "${kind}" in
    file)
      copy_file "${source_path}" "${destination_path}"
      ;;
    tree)
      mkdir -p "${destination_path}"
      cp -R "${source_path}/." "${destination_path}/"
      ;;
    *)
      log "unsupported publication entry type: ${kind}"
      return 1
      ;;
  esac
}

main() {
  require_file "${ROOT}/actions/build.docs.sh"
  require_file "${ROOT}/actions/lib/publication.sh"
  require_file "${PUBLICATION_MANIFEST}"
  require_file "${ROOT}/docs/readme.md"
  require_file "${ROOT}/docs/_templates/page.html"
  require_file "${ROOT}/docs/_assets/site.css"

  publication.manifest.validate "${PUBLICATION_MANIFEST}"
  publication.manifest.require.core.sources "${PUBLICATION_MANIFEST}"
  if ! PUBLISH_DIR="$(publication.output.path.resolve "${PUBLISH_DIR_REQUESTED}" "${ROOT}")"; then
    log "publish directory cannot be resolved below an existing parent: ${PUBLISH_DIR_REQUESTED}"
    exit 1
  fi
  if ! publication.output.path.is.safe "${PUBLISH_DIR}"; then
    log "refusing unsafe publish directory: ${PUBLISH_DIR}"
    exit 1
  fi

  rm -rf -- "${PUBLISH_DIR}"
  mkdir -p "${PUBLISH_DIR}"
  publication.manifest.each "${PUBLICATION_MANIFEST}" publish.manifest.entry

  DOCS_SITE_ROOT="${DOCS_SITE_ROOT:-/debian}" \
    bash "${ROOT}/actions/build.docs.sh" \
      --source "${ROOT}/docs" \
      --output "${PUBLISH_DIR}"

  log "published static tree at ${PUBLISH_DIR}"
}

main "$@"
