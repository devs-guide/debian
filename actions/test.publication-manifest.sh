#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${REPO_ROOT}"
PUBLICATION_LABEL="test.publication-manifest"
REAL_MANIFEST="${ROOT}/actions/publication.manifest"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "${TEST_PARENT%/}/test.publication-manifest.XXXXXX")"
rc=0

# shellcheck source=actions/lib/publication.sh
source "${ROOT}/actions/lib/publication.sh"

echo "[test.publication-manifest] checking parser failures and canonical publication inventory..."

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && "${TEST_ROOT}" == "${TEST_PARENT%/}/test.publication-manifest."* ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

fail() {
  printf '[test.publication-manifest][error] %s\n' "$*" >&2
  rc=1
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "${label}: expected failure"
  fi
}

record.entry() {
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "${TEST_ROOT}/entries.log"
}

fixture_root="${TEST_ROOT}/repository"
mkdir -p "${fixture_root}/setup/cli" "${fixture_root}/ansible"
printf '%s\n' '#!/usr/bin/env bash' > "${fixture_root}/setup/cli/example.sh"
printf '%s\n' '---' > "${fixture_root}/ansible/example.yml"
printf '%s\n' '# fixture' > "${fixture_root}/readme.md"

valid_manifest="${TEST_ROOT}/valid.manifest"
printf '%s\n' \
  'file|setup/cli/example.sh|setup/cli/example.sh' \
  'tree|ansible|ansible' \
  'file|readme.md|readme.md' > "${valid_manifest}"

ROOT="${fixture_root}"
publication.manifest.validate "${valid_manifest}" || fail "valid fixture manifest was rejected"
publication.manifest.require.setup.runners "${valid_manifest}" || fail "valid fixture omitted a setup runner"
publication.manifest.each "${valid_manifest}" record.entry || fail "valid fixture iteration failed"
if [[ "$(wc -l < "${TEST_ROOT}/entries.log")" -ne 3 ]]; then
  fail "valid fixture did not iterate exactly three entries"
fi

invalid_manifest="${TEST_ROOT}/invalid.manifest"
printf '%s\n' 'file|setup/cli/example.sh|setup/cli/example' > "${invalid_manifest}"
expect_failure "extensionless setup destination" publication.manifest.validate "${invalid_manifest}"
printf '%s\n' 'file|../escape.sh|setup/escape.sh' > "${invalid_manifest}"
expect_failure "unsafe source" publication.manifest.validate "${invalid_manifest}"
printf '%s\n' \
  'file|readme.md|readme.md' \
  'file|setup/cli/example.sh|readme.md' > "${invalid_manifest}"
expect_failure "duplicate destination" publication.manifest.validate "${invalid_manifest}"
printf '%s\n' \
  'tree|ansible|ansible' \
  'file|ansible/example.yml|published/example.yml' > "${invalid_manifest}"
expect_failure "overlapping source tree" publication.manifest.validate "${invalid_manifest}"
printf '%s\n' \
  'tree|ansible|ansible' \
  'file|readme.md|ansible/readme.md' > "${invalid_manifest}"
expect_failure "overlapping destination tree" publication.manifest.validate "${invalid_manifest}"
printf '%s\n' 'file|missing.sh|missing.sh' > "${invalid_manifest}"
expect_failure "missing source" publication.manifest.validate "${invalid_manifest}"
: > "${fixture_root}/empty.md"
printf '%s\n' 'file|empty.md|empty.md' > "${invalid_manifest}"
expect_failure "empty source" publication.manifest.validate "${invalid_manifest}"

ROOT="${REPO_ROOT}"
publication.manifest.validate "${REAL_MANIFEST}" || fail "repository publication manifest is invalid"
publication.manifest.require.core.sources "${REAL_MANIFEST}" || fail "repository publication inventory is incomplete"
resolved_relative_output="$(
  publication.output.path.resolve static "${REPO_ROOT}"
)" || fail "repository-relative publish output could not be resolved"
if [[ "${resolved_relative_output}" != "${REPO_ROOT}/static" ]]; then
  fail "repository-relative publish output resolved unexpectedly: ${resolved_relative_output}"
fi
publication.output.path.is.safe "${TEST_ROOT}/publish-output" || fail "isolated publish output was rejected"
publication.output.path.is.safe "${REPO_ROOT}/static" || fail "canonical static output was rejected"
expect_failure "filesystem root output" publication.output.path.is.safe /
if [[ -n "${HOME:-}" ]]; then
  expect_failure "home output" publication.output.path.is.safe "${HOME}"
fi

exit "${rc}"
