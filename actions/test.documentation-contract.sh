#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.documentation-contract"
rc=0

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking canonical setup URLs and documentation sources..."

for file in \
  actions/lib/contracts.sh \
  actions/lib/publication.sh \
  actions/publication.manifest \
  docs/_templates/page.html \
  docs/_assets/site.css; do
  require_file "${file}"
done
require_contains "actions/lib/contracts.sh" 'command -v rg'
require_contains "actions/lib/contracts.sh" 'grep -R -nE'
require_shell_syntax "actions/build.docs.sh"
require_shell_syntax "actions/www.pages.sh"
require_shell_syntax "actions/validate.pages.sh"

for marker in \
  'command -v pandoc' \
  'is_publishable_markdown' \
  'canonical document requires title and section front matter' \
  '_templates/page.html'; do
  require_contains "actions/build.docs.sh" "${marker}"
done

require_contains "actions/www.pages.sh" 'actions/build.docs.sh'
require_contains "actions/www.pages.sh" 'actions/publication.manifest'
require_contains "actions/www.pages.sh" 'actions/lib/publication.sh'
require_contains "actions/www.pages.sh" 'publication.manifest.each'
require_contains "actions/validate.pages.sh" 'actions/publication.manifest'
require_contains "actions/validate.pages.sh" 'actions/lib/publication.sh'
require_contains "actions/validate.pages.sh" 'publication.manifest.each'
reject_contains "actions/www.pages.sh" 'www/index.html:index.html'
reject_contains "actions/www.pages.sh" 'cp -R "${ROOT}/docs"'
reject_contains "actions/www.pages.sh" 'local -a root_files='
reject_contains "actions/validate.pages.sh" 'FILES=('

published_setup_url_prefix_ere='(https://devs-guide\.github\.io/debian/|\$\{PAGES_BASE_URL\}/)'
published_setup_url_delimiter_ere='([[:space:]"`|)}]|$)'
while IFS= read -r published_setup_source; do
  extensionless_source="${published_setup_source%.sh}"
  escaped_extensionless_source="$(
    printf '%s\n' "${extensionless_source}" \
      | sed 's/[][\\.^$*+?{}|()]/\\&/g'
  )"
  if search_regex \
    "${published_setup_url_prefix_ere}${escaped_extensionless_source}${published_setup_url_delimiter_ere}" \
    "${ROOT}/setup"; then
    contract.error "published setup entrypoint URL is missing its canonical .sh extension: ${extensionless_source}"
  fi
done < <(
  awk -F'|' '$1 == "file" && $2 ~ /^setup\// { print $2 }' \
    "${ROOT}/actions/publication.manifest"
)

while IFS= read -r document; do
  relative="${document#"${ROOT}/"}"
  if [[ "$(sed -n '1p' "${document}")" != '---' ]] || \
    ! grep -Eq '^title:[[:space:]]+.+$' "${document}" || \
    ! grep -Eq '^section:[[:space:]]+.+$' "${document}"; then
    contract.error "canonical documentation is missing required front matter: ${relative}"
  fi
done < <(find "${ROOT}/docs" -type f -name readme.md | sort)

exit "${rc}"
