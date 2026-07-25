#!/usr/bin/env bash

# Render the canonical Markdown documentation tree into the GitHub Pages
# publish directory. This script intentionally does not install Pandoc: local
# users can review source files without a renderer, while CI provides the
# deterministic rendering dependency.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT}/docs"
OUTPUT_DIR="${ROOT}/static"
SITE_ROOT="${DOCS_SITE_ROOT:-/debian}"

log() {
  printf '[build.docs] %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: bash actions/build.docs.sh [--source DIR] [--output DIR] [--site-root PATH]

Render the canonical docs tree into an existing static publish directory.
Pandoc must already be installed; this script never installs dependencies.
EOF
}

while (($#)); do
  case "$1" in
    --source)
      SOURCE_DIR="${2:?--source requires a directory}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:?--output requires a directory}"
      shift 2
      ;;
    --site-root)
      SITE_ROOT="${2:?--site-root requires a path}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log "unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "${SOURCE_DIR}" ]]; then
  log "documentation source directory is missing: ${SOURCE_DIR}"
  exit 1
fi
if ! command -v pandoc >/dev/null 2>&1; then
  log "pandoc is required to render documentation; install it in CI or use a prepared documentation environment"
  exit 1
fi

TEMPLATE="${SOURCE_DIR}/_templates/page.html"
STYLESHEET="${SOURCE_DIR}/_assets/site.css"
for required in "${TEMPLATE}" "${STYLESHEET}" "${SOURCE_DIR}/readme.md"; do
  if [[ ! -f "${required}" ]]; then
    log "missing required documentation input: ${required}"
    exit 1
  fi
done

mkdir -p "${OUTPUT_DIR}" "${OUTPUT_DIR}/assets/docs"
cp "${STYLESHEET}" "${OUTPUT_DIR}/assets/docs/site.css"

is_publishable_markdown() {
  local relative="$1"

  case "${relative}" in
    readme.md|\
    cli/readme.md|cli/*/readme.md|\
    setup/readme.md|setup/*/readme.md|\
    ansible/readme.md|ansible/*/readme.md|\
    actions/readme.md|actions/*/readme.md|actions/*/*/readme.md|\
    kiosk/readme.md|kiosk/*/readme.md|kiosk/*/*/readme.md|\
    history/readme.md|history/*/readme.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

frontmatter_value() {
  local file="$1"
  local key="$2"

  awk -v key="${key}" '
    NR == 1 {
      if ($0 != "---") {
        exit 2
      }
      next
    }
    $0 == "---" {
      exit
    }
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "${file}"
}

destination_for() {
  local relative="$1"
  local dirname

  if [[ "${relative}" == "readme.md" ]]; then
    printf '%s/index.html\n' "${OUTPUT_DIR}"
    return
  fi

  dirname="${relative%/readme.md}"
  printf '%s/%s/index.html\n' "${OUTPUT_DIR}" "${dirname}"
}

breadcrumb_label() {
  local component="$1"

  case "${component}" in
    cli) printf 'CLI' ;;
    setup) printf 'Setup' ;;
    ansible) printf 'Ansible' ;;
    actions) printf 'Actions' ;;
    kiosk) printf 'Kiosk' ;;
    history) printf 'History' ;;
    nvidia) printf 'NVIDIA' ;;
    nvlink) printf 'NVLink' ;;
    startx) printf 'STARTX' ;;
    x11) printf 'X11' ;;
    codex) printf 'Codex' ;;
    node) printf 'Node' ;;
    kiosk.app) printf 'Kiosk app' ;;
    openbox) printf 'Openbox' ;;
    touchscreen) printf 'Touchscreen' ;;
    tauri) printf 'Tauri' ;;
    bootstrap) printf 'Bootstrap' ;;
    debian) printf 'Debian' ;;
    metal) printf 'Metal' ;;
    hardware) printf 'Hardware' ;;
    autologin) printf 'Autologin' ;;
    packages) printf 'Packages' ;;
    users) printf 'Users' ;;
    build-docs) printf 'Build documentation' ;;
    publish) printf 'Publish' ;;
    validate) printf 'Validate' ;;
    runtime) printf 'Runtime' ;;
    pages) printf 'Pages' ;;
    test) printf 'Test' ;;
    sudo-access) printf 'Sudo access' ;;
    runner-staging) printf 'Runner staging' ;;
    nvidia-facts) printf 'NVIDIA facts' ;;
    release-common) printf 'Release helper' ;;
    runner-common) printf 'Shared runner' ;;
    essential-packages) printf 'Essential packages' ;;
    prerequisites) printf 'Prerequisites' ;;
    app-launch) printf 'Application launch' ;;
    autologin-orchestration) printf 'Autologin orchestration' ;;
    remote-debug) printf 'Remote debug' ;;
    reference) printf 'Reference' ;;
    kiosk-auto-app-rename) printf 'Kiosk auto-app rename' ;;
    *) printf '%s' "${component}" ;;
  esac
}

breadcrumb_url() {
  local route="$1"

  if [[ "${SITE_ROOT}" == "/" ]]; then
    printf '/%s/\n' "${route}"
  else
    printf '%s/%s/\n' "${SITE_ROOT%/}" "${route}"
  fi
}

breadcrumb_metadata() {
  local relative="$1"
  local route="${relative%/readme.md}"
  local component=""
  local assembled=""
  local index=0
  local -a components=()

  BREADCRUMB_METADATA=()
  if [[ "${relative}" == "readme.md" ]]; then
    return
  fi

  IFS='/' read -r -a components <<< "${route}"
  for component in "${components[@]}"; do
    [[ -n "${component}" ]] || continue
    if [[ -n "${assembled}" ]]; then
      assembled+="/"
    fi
    assembled+="${component}"
    index=$((index + 1))

    if (( index == ${#components[@]} )); then
      BREADCRUMB_METADATA+=(
        --metadata "breadcrumb_current_label=$(breadcrumb_label "${component}")"
        --metadata "breadcrumb_current_url=$(breadcrumb_url "${assembled}")"
      )
    else
      BREADCRUMB_METADATA+=(
        --metadata "breadcrumb_${index}_label=$(breadcrumb_label "${component}")"
        --metadata "breadcrumb_${index}_url=$(breadcrumb_url "${assembled}")"
      )
    fi
  done
}

declare -a destinations=()
while IFS= read -r -d '' source_file; do
  relative="${source_file#"${SOURCE_DIR}"/}"
  if ! is_publishable_markdown "${relative}"; then
    continue
  fi

  title="$(frontmatter_value "${source_file}" title || true)"
  section="$(frontmatter_value "${source_file}" section || true)"
  source_path="$(frontmatter_value "${source_file}" source_path || true)"
  if [[ -z "${title}" || -z "${section}" ]]; then
    log "canonical document requires title and section front matter: ${relative}"
    exit 1
  fi
  if [[ -n "${source_path}" && ! -e "${ROOT}/${source_path}" ]]; then
    log "document source_path does not exist: ${relative} -> ${source_path}"
    exit 1
  fi

  destination="$(destination_for "${relative}")"
  for existing in "${destinations[@]}"; do
    if [[ "${existing}" == "${destination}" ]]; then
      log "multiple documents resolve to ${destination}"
      exit 1
    fi
  done
  destinations+=("${destination}")

  mkdir -p "$(dirname "${destination}")"
  breadcrumb_metadata "${relative}"
  log "render ${relative} -> ${destination#"${OUTPUT_DIR}"/}"
  pandoc \
    --from=gfm+yaml_metadata_block \
    --to=html5 \
    --standalone \
    --template="${TEMPLATE}" \
    --metadata "site_root=${SITE_ROOT}" \
    "${BREADCRUMB_METADATA[@]}" \
    "${source_file}" \
    --output="${destination}"
done < <(find "${SOURCE_DIR}" -type f -name '*.md' -print0 | sort -z)

raw_files=(
  'history/www.index.legacy.html'
  'kiosk/reference/legacy-command-sequence.txt'
  'kiosk/reference/screen-commands.txt'
  'kiosk/reference/touchscreen-notes.txt'
  'kiosk/reference/xorg-touch.config'
)

for relative in "${raw_files[@]}"; do
  source_file="${SOURCE_DIR}/${relative}"
  destination="${OUTPUT_DIR}/${relative}"
  if [[ ! -f "${source_file}" ]]; then
    log "missing canonical raw documentation file: ${relative}"
    exit 1
  fi
  mkdir -p "$(dirname "${destination}")"
  cp "${source_file}" "${destination}"
done

log "rendered ${#destinations[@]} canonical documentation pages into ${OUTPUT_DIR}"
