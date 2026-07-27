#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_HELPER="${ROOT}/setup/runner.common.sh"
RELEASE_HELPER="${ROOT}/setup/release.common.sh"
TEST_TMP_PARENT="${TMPDIR:-/tmp}"
TEST_TMP="$(mktemp -d "${TEST_TMP_PARENT%/}/test.runner-staging.XXXXXX")"
rc=0
case_index=0
CASE_OUTPUT=""
CASE_STATUS=0

cleanup() {
  if [[ -n "${TEST_TMP:-}" && "${TEST_TMP}" == "${TEST_TMP_PARENT%/}/test.runner-staging."* ]]; then
    rm -rf -- "${TEST_TMP}"
  fi
}
trap cleanup EXIT

fail() {
  printf '[test.runner-staging][error] %s\n' "$*" >&2
  rc=1
}

expect_status() {
  local expected="$1" actual="$2" label="$3"
  [[ "${actual}" -eq "${expected}" ]] || \
    fail "${label}: expected status ${expected}, got ${actual}"
}

expect_contains() {
  local needle="$1" haystack="$2" label="$3"
  [[ "${haystack}" == *"${needle}"* ]] || fail "${label}: missing ${needle}"
}

expect_not_contains() {
  local needle="$1" haystack="$2" label="$3"
  [[ "${haystack}" != *"${needle}"* ]] || fail "${label}: unexpectedly contained ${needle}"
}

run_case() {
  local label="$1"
  local script="$2"
  local runner="${3:-}"
  local case_root=""
  local result=""
  local status_code=0

  case_index=$((case_index + 1))
  case_root="${TEST_TMP}/case-${case_index}"
  mkdir -p "${case_root}"

  set +e
  result="$(
    /usr/bin/env -i \
      HOME="${HOME:-/tmp}" \
      PATH="/usr/local/bin:/usr/bin:/bin" \
      TEST_CASE_ROOT="${case_root}" \
      TEST_HELPER="${RUNNER_HELPER}" \
      TEST_RELEASE="${RELEASE_HELPER}" \
      TEST_RUNNER="${runner}" \
      /bin/bash -c "${script}" 2>&1
  )"
  status_code=$?
  set -e

  CASE_OUTPUT="${result}"
  CASE_STATUS="${status_code}"
  printf '[test.runner-staging] %s\n' "${label}"
  if [[ -n "${CASE_OUTPUT}" ]]; then
    printf '%s\n' "${CASE_OUTPUT}"
  fi
}

run_case "local declarative Ansible manifest" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  source_root="${TEST_CASE_ROOT}/source"
  mkdir -p \
    "${source_root}/group_vars" \
    "${source_root}/cli" \
    "${source_root}/files/test" \
    "${source_root}/templates"
  printf "%s\n" "---" "fixture: group-vars" > "${source_root}/group_vars/all.yml"
  printf "%s\n" "---" "- hosts: localhost" > "${source_root}/cli/test.yml"
  printf "%s\n" "runtime fixture" > "${source_root}/files/test/runtime.txt"
  printf "%s\n" "template fixture" > "${source_root}/templates/test.j2"
  GROUP_VARS_FILES=("all.yml")
  FEATURE_PLAYBOOKS=("cli/test.yml")
  RUNTIME_SUPPORT_REFS=("files/test/runtime.txt")
  FEATURE_TEMPLATE_REFS=("templates/test.j2")
  wget() {
    printf "unexpected wget\n"
    return 99
  }
  runner.stage.ansible.feature \
    "${source_root}" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime"
  [[ "${RUNNER_STAGE_SOURCE}" == local ]]
  cmp "${source_root}/group_vars/all.yml" "${RUNNER_RUNTIME_DIR}/runtime/group_vars/all.yml"
  cmp "${source_root}/cli/test.yml" "${RUNNER_RUNTIME_DIR}/runtime/cli/test.yml"
  cmp "${source_root}/files/test/runtime.txt" "${RUNNER_RUNTIME_DIR}/runtime/files/test/runtime.txt"
  cmp "${source_root}/templates/test.j2" "${RUNNER_RUNTIME_DIR}/runtime/templates/test.j2"
  printf "LOCAL_OK\n"
'
expect_status 0 "${CASE_STATUS}" "local manifest"
expect_contains 'LOCAL_OK' "${CASE_OUTPUT}" "local manifest"
expect_not_contains 'unexpected wget' "${CASE_OUTPUT}" "local manifest"

run_case "missing declarative array fails with a contract error" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  GROUP_VARS_FILES=("all.yml")
  FEATURE_PLAYBOOKS=("cli/test.yml")
  RUNTIME_SUPPORT_REFS=()
  unset FEATURE_TEMPLATE_REFS
  wget() {
    printf "unexpected wget\n"
    return 99
  }
  if runner.stage.ansible.feature \
    "" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime"; then
    exit 90
  fi
  printf "MISSING_ARRAY_BLOCKED\n"
'
expect_status 0 "${CASE_STATUS}" "missing declarative array"
expect_contains 'Required runner manifest array is not declared: FEATURE_TEMPLATE_REFS' "${CASE_OUTPUT}" "missing declarative array"
expect_contains 'MISSING_ARRAY_BLOCKED' "${CASE_OUTPUT}" "missing declarative array"
expect_not_contains 'unexpected wget' "${CASE_OUTPUT}" "missing declarative array"

for feature_runner in \
  setup/cli/gpu.sh \
  setup/cli/llm/host.sh \
  setup/cli/llm/llamacpp.sh \
  setup/cli/llm/ktransformers.sh \
  setup/cli/nvidia.sh \
  setup/cli/nvlink.sh; do
  run_case "${feature_runner} stages its complete local manifest" '
    source "${TEST_RUNNER}"
    source.runner.common
    source.release.common
    prepare.feature.files
    [[ "${RUNNER_STAGE_SOURCE}" == local ]]
    for reference in "${GROUP_VARS_FILES[@]}"; do
      [[ -s "${PLAYBOOK_ROOT}/group_vars/${reference}" ]]
    done
    for reference in "${FEATURE_PLAYBOOKS[@]}"; do
      [[ -s "${PLAYBOOK_ROOT}/${reference}" ]]
    done
    for reference in "${RUNTIME_SUPPORT_REFS[@]}"; do
      [[ -s "${PLAYBOOK_ROOT}/${reference}" ]]
    done
    if ((${#FEATURE_TEMPLATE_REFS[@]} > 0)); then
      for reference in "${FEATURE_TEMPLATE_REFS[@]}"; do
        [[ -s "${PLAYBOOK_ROOT}/${reference}" ]]
      done
    fi
    printf "FEATURE_MANIFEST_OK\n"
  ' "${ROOT}/${feature_runner}"
  expect_status 0 "${CASE_STATUS}" "${feature_runner} complete local manifest"
  expect_contains 'FEATURE_MANIFEST_OK' "${CASE_OUTPUT}" "${feature_runner} complete local manifest"
done

for feature_runner in setup/cli/gpu.sh setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  run_case "${feature_runner} rejects an incomplete local checkout" '
    partial_root="${TEST_CASE_ROOT}/partial"
    mkdir -p "${partial_root}/setup/cli"
    cp "${TEST_HELPER}" "${partial_root}/setup/runner.common.sh"
    cp "${TEST_RUNNER}" "${partial_root}/setup/cli/${TEST_RUNNER##*/}"
    wget() {
      printf "unexpected wget\n"
      return 99
    }
    if (
      source "${partial_root}/setup/cli/${TEST_RUNNER##*/}"
      source.runner.common
      source.release.common
    ); then
      exit 90
    else
      status_code=$?
    fi
    [[ "${status_code}" -eq 3 ]]
    printf "INCOMPLETE_LOCAL_BLOCKED\n"
  ' "${ROOT}/${feature_runner}"
  expect_status 0 "${CASE_STATUS}" "${feature_runner} incomplete local checkout"
  expect_contains 'shared release helper local dependency is unavailable' "${CASE_OUTPUT}" "${feature_runner} incomplete local checkout"
  expect_contains 'INCOMPLETE_LOCAL_BLOCKED' "${CASE_OUTPUT}" "${feature_runner} incomplete local checkout"
  expect_not_contains 'unexpected wget' "${CASE_OUTPUT}" "${feature_runner} incomplete local checkout"
done

run_case "published manifest uses the shared fetch path" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  trace="${TEST_CASE_ROOT}/wget.trace"
  wget() {
    [[ "$#" -eq 3 && "$1" == -qO ]] || return 98
    printf "%s\n" "$3" >> "${trace}"
    printf "downloaded=%s\n" "$3" > "$2"
  }
  runner.stage.manifest \
    "" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime" \
    "published fixture" \
    "group_vars/all.yml" \
    "cli/test.yml"
  [[ "${RUNNER_STAGE_SOURCE}" == published ]]
  [[ "$(wc -l < "${trace}")" -eq 2 ]]
  grep -Fq "https://example.invalid/ansible/group_vars/all.yml" "${trace}"
  grep -Fq "https://example.invalid/ansible/cli/test.yml" "${trace}"
  printf "REMOTE_OK\n"
'
expect_status 0 "${CASE_STATUS}" "published manifest"
expect_contains 'REMOTE_OK' "${CASE_OUTPUT}" "published manifest"

run_case "missing local dependency fails before partial staging" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  source_root="${TEST_CASE_ROOT}/source"
  mkdir -p "${source_root}"
  printf "%s\n" "present" > "${source_root}/present.yml"
  wget() {
    printf "unexpected wget\n"
    return 99
  }
  if runner.stage.manifest \
    "${source_root}" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime" \
    "missing-local fixture" \
    "present.yml" \
    "missing.yml"; then
    exit 90
  fi
  [[ ! -e "${RUNNER_RUNTIME_DIR}/runtime/present.yml" ]]
  printf "MISSING_LOCAL_BLOCKED\n"
'
expect_status 0 "${CASE_STATUS}" "missing local dependency"
expect_contains 'MISSING_LOCAL_BLOCKED' "${CASE_OUTPUT}" "missing local dependency"
expect_not_contains 'unexpected wget' "${CASE_OUTPUT}" "missing local dependency"

run_case "empty download is rejected and cleaned" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  wget() {
    [[ "$#" -eq 3 && "$1" == -qO ]] || return 98
    : > "$2"
  }
  if runner.stage.manifest \
    "" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime" \
    "empty-download fixture" \
    "empty.yml"; then
    exit 90
  fi
  [[ ! -e "${RUNNER_RUNTIME_DIR}/runtime/empty.yml" ]]
  [[ -z "$(find "${RUNNER_RUNTIME_DIR}/runtime" -name "*.part.*" -print -quit)" ]]
  printf "EMPTY_DOWNLOAD_BLOCKED\n"
'
expect_status 0 "${CASE_STATUS}" "empty download"
expect_contains 'EMPTY_DOWNLOAD_BLOCKED' "${CASE_OUTPUT}" "empty download"

run_case "failed finalization removes the partial file" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  wget() {
    [[ "$#" -eq 3 && "$1" == -qO ]] || return 98
    printf "%s\n" "complete payload" > "$2"
  }
  mv() {
    return 1
  }
  if runner.stage.manifest \
    "" \
    "https://example.invalid/ansible" \
    "${RUNNER_RUNTIME_DIR}/runtime" \
    "failed-finalization fixture" \
    "move-failure.yml"; then
    exit 90
  fi
  [[ ! -e "${RUNNER_RUNTIME_DIR}/runtime/move-failure.yml" ]]
  [[ -z "$(find "${RUNNER_RUNTIME_DIR}/runtime" -name "*.part.*" -print -quit)" ]]
  printf "FINALIZATION_BLOCKED\n"
'
expect_status 0 "${CASE_STATUS}" "failed finalization"
expect_contains 'FINALIZATION_BLOCKED' "${CASE_OUTPUT}" "failed finalization"

run_case "unsafe and duplicate manifest entries fail closed" '
  source "${TEST_HELPER}"
  runner.create.runtime staging "${TEST_CASE_ROOT}"
  wget() {
    printf "unexpected wget\n"
    return 99
  }
  if runner.stage.manifest "" "https://example.invalid" "${RUNNER_RUNTIME_DIR}/runtime" unsafe "../escape.yml"; then exit 90; fi
  if runner.stage.manifest "" "https://example.invalid" "${RUNNER_RUNTIME_DIR}/runtime" unsafe "/escape.yml"; then exit 91; fi
  if runner.stage.manifest "" "https://example.invalid" "${RUNNER_RUNTIME_DIR}/runtime" duplicate "same.yml" "same.yml"; then exit 92; fi
  if runner.stage.manifest "" "https://example.invalid" "${RUNNER_RUNTIME_DIR}/../escape" outside "safe.yml"; then exit 93; fi
  printf "UNSAFE_BLOCKED\n"
'
expect_status 0 "${CASE_STATUS}" "unsafe manifest"
expect_contains 'UNSAFE_BLOCKED' "${CASE_OUTPUT}" "unsafe manifest"
expect_not_contains 'unexpected wget' "${CASE_OUTPUT}" "unsafe manifest"

run_case "release helper does not overwrite feature manifests" '
  RUNTIME_SUPPORT_REFS=("feature-only.yml")
  source "${TEST_RELEASE}"
  [[ "${RUNTIME_SUPPORT_REFS[*]}" == "feature-only.yml" ]]
  [[ "${RELEASE_RUNTIME_SUPPORT_REFS[*]}" == "packages.yml ssh.yml" ]]
  printf "NAMESPACE_OK\n"
'
expect_status 0 "${CASE_STATUS}" "release helper namespace"
expect_contains 'NAMESPACE_OK' "${CASE_OUTPUT}" "release helper namespace"

exit "${rc}"
