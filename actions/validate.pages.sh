#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-https://devs-guide.github.io/debian}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLICATION_MANIFEST="${ROOT}/actions/publication.manifest"
PUBLICATION_LABEL="validate.pages"
WORK_PARENT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${WORK_PARENT%/}/validate.pages.XXXXXX")"
DOCS_RENDER_DIR="${WORK_DIR}/rendered-docs"
rc=0

# shellcheck source=actions/lib/publication.sh
source "${ROOT}/actions/lib/publication.sh"

cleanup() {
  if [[ -n "${WORK_DIR:-}" && "${WORK_DIR}" == "${WORK_PARENT%/}/validate.pages."* ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
}
trap cleanup EXIT

base_without_scheme="${BASE_URL#*://}"
if [[ "${base_without_scheme}" == */* ]]; then
  DOCS_SITE_ROOT="/${base_without_scheme#*/}"
else
  DOCS_SITE_ROOT="/"
fi
DOCS_SITE_ROOT="/${DOCS_SITE_ROOT#/}"
DOCS_SITE_ROOT="${DOCS_SITE_ROOT%/}"
[[ -n "${DOCS_SITE_ROOT}" ]] || DOCS_SITE_ROOT="/"
BASE_URL="${BASE_URL%/}"

compare.published.file() {
  local local_file="$1"
  local remote_path="$2"
  local destination="${WORK_DIR}/published/${remote_path}"
  local url="${BASE_URL}/${remote_path}"

  mkdir -p "$(dirname "${destination}")"
  echo "[validate.pages] fetch ${url}"
  if ! curl -fsSL "${url}" -o "${destination}"; then
    echo "[validate.pages][error] failed to fetch ${url}"
    rc=1
    return
  fi
  if ! diff -u "${local_file}" "${destination}" >/dev/null; then
    echo "[validate.pages][diff] ${local_file#"${ROOT}/"} differs from ${url}"
    diff -u "${local_file}" "${destination}" || true
    rc=1
  else
    echo "[validate.pages][ok] ${remote_path}"
  fi
}

validate.manifest.entry() {
  local kind="$1"
  local source="$2"
  local destination="$3"
  local source_path="${ROOT}/${source}"
  local local_file=""
  local relative=""

  case "${kind}" in
    file)
      compare.published.file "${source_path}" "${destination}"
      ;;
    tree)
      while IFS= read -r local_file; do
        relative="${local_file#"${source_path}/"}"
        compare.published.file "${local_file}" "${destination}/${relative}"
      done < <(find "${source_path}" -type f | sort)
      ;;
    *)
      echo "[validate.pages][error] unsupported publication entry type: ${kind}"
      rc=1
      ;;
  esac
}

validate.rendered.documentation() {
  local local_file=""
  local relative=""

  while IFS= read -r local_file; do
    relative="${local_file#"${DOCS_RENDER_DIR}/"}"
    compare.published.file "${local_file}" "${relative}"
  done < <(find "${DOCS_RENDER_DIR}" -type f | sort)
}

echo "[validate.pages] using BASE_URL=${BASE_URL}"
echo "[validate.pages] temp dir: ${WORK_DIR}"
echo "[validate.pages] publication manifest: ${PUBLICATION_MANIFEST}"

if ! command -v curl >/dev/null 2>&1; then
  echo "[validate.pages][error] curl is required"
  exit 1
fi
if ! publication.manifest.validate "${PUBLICATION_MANIFEST}"; then
  exit 1
fi
if ! publication.manifest.require.core.sources "${PUBLICATION_MANIFEST}"; then
  exit 1
fi

echo "[validate.pages] render canonical docs with site root: ${DOCS_SITE_ROOT}"
if ! DOCS_SITE_ROOT="${DOCS_SITE_ROOT}" bash "${ROOT}/actions/build.docs.sh" \
  --source "${ROOT}/docs" \
  --output "${DOCS_RENDER_DIR}" \
  --site-root "${DOCS_SITE_ROOT}"; then
  echo "[validate.pages][error] could not render canonical documentation for comparison"
  exit 1
fi

publication.manifest.each "${PUBLICATION_MANIFEST}" validate.manifest.entry
validate.rendered.documentation

exit "${rc}"
