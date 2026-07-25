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

require.runner.options.documented() {
  local runner="$1"
  local document="$2"
  local option=""

  while IFS= read -r option; do
    if ! grep -Fq -- "${option}" "${ROOT}/${document}"; then
      contract.error "${document} does not document runner option ${option} from ${runner}"
    fi
  done < <(
    sed -n '/^Options:/,/^$/p' "${ROOT}/${runner}" \
      | grep -Eo -- '--[a-z0-9-]+' \
      | sort -u
  )
}
require.runner.options.documented "setup/cli/nvidia.sh" "docs/cli/nvidia/readme.md"
require.runner.options.documented "setup/cli/nvlink.sh" "docs/cli/nvlink/readme.md"
require.runner.options.documented "setup/cli/gpu.sh" "docs/cli/gpu/readme.md"

for document in docs/cli/gpu/readme.md docs/cli/nvidia/readme.md docs/cli/nvlink/readme.md; do
  for marker in \
    'wget -qO- https://devs-guide.github.io/debian/setup/cli/' \
    '/dev/tty'; do
    require_contains "${document}" "${marker}"
  done
  require_regex "${document}" '^[[:space:]]+bash -s -- preflight([[:space:]]|$)'
  require_regex "${document}" '^[[:space:]]+bash -s -- apply([[:space:]]|$)'
  require_regex "${document}" '^[[:space:]]+sudo bash -s -- (apply|validate)([[:space:]]|$)'
done
require_contains "docs/cli/gpu/readme.md" '/etc/ansible/debian/facts/gpu.yml'
require_contains "docs/cli/nvidia/readme.md" '/etc/ansible/debian/facts/nvidia.yml'
require_contains "docs/cli/nvidia/readme.md" '/etc/ansible/debian/facts/gpu.yml'
require_contains "docs/cli/nvlink/readme.md" '/etc/ansible/debian/facts/nvidia.yml'
require_contains "docs/cli/nvlink/readme.md" '/etc/ansible/debian/facts/gpu.yml'
require_contains "docs/cli/nvlink/readme.md" '/etc/ansible/debian/facts/nvlink.yml'
if grep -R -nF -- '--apply' "${ROOT}/docs"; then
  contract.error "documentation must pass apply as a positional mode: bash -s -- apply"
fi

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

while IFS= read -r legacy_action_document; do
  contract.error "noncanonical action document must be merged into a route readme or history: ${legacy_action_document#"${ROOT}/"}"
done < <(
  find "${ROOT}/docs/actions" -mindepth 1 -maxdepth 1 \
    -type f -name '*.md' ! -name readme.md | sort
)

exit "${rc}"
