#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.ipmctl-contract"
NETWORK_VERIFY="${IPMCTL_SOURCE_NETWORK_VERIFY:-0}"
rc=0
SHELL_ONLY=0

case "${1:-}" in
  "") ;;
  --shell-only) SHELL_ONLY=1 ;;
  *)
    echo "[${ACTION_LABEL}][error] usage: bash actions/test.ipmctl-contract.sh [--shell-only]" >&2
    exit 64
    ;;
esac

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking pinned ipmctl and guarded-goal contracts..."

for file in \
  setup/cli/ipmctl.sh \
  ansible/cli/ipmctl.yml \
  ansible/files/ipmctl/source-profile.py \
  ansible/files/ipmctl/ipmctl-inventory.py \
  ansible/files/ipmctl/compatibility-matrix.yml \
  actions/test.ipmctl-source-build.sh \
  docs/cli/ipmctl/readme.md \
  actions/fixtures/ipmctl/memory-mode/version.txt \
  actions/fixtures/ipmctl/memory-mode/memory-resources.txt \
  actions/fixtures/ipmctl/app-direct/memory-resources.txt \
  actions/fixtures/ipmctl/app-direct/regions.txt \
  actions/fixtures/ipmctl/unsupported/capabilities.txt \
  actions/fixtures/ipmctl/malformed/dimms.txt \
  actions/fixtures/ipmctl/namespaces/ndctl-namespaces.txt \
  actions/fixtures/ipmctl/pending-goal/goal.txt \
  actions/fixtures/ipmctl/partial-failure/topology.rc; do
  require_file "${file}"
done

require_shell_syntax "setup/cli/ipmctl.sh"
for marker in \
  'FEATURE_PLAYBOOKS=("install.packages.yml" "cli/ipmctl.yml")' \
  'files/ipmctl/source-profile.py' \
  'files/ipmctl/ipmctl-inventory.py' \
  'files/ipmctl/compatibility-matrix.yml' \
  '--commit=FULL_40_CHARACTER_SHA' \
  '--edk2-commit=FULL_40_CHARACTER_SHA' \
  '--goal=memory-mode|app-direct|app-direct-not-interleaved' \
  '--allow-destructive-goal-change' \
  'runner.confirm.exact' \
  'GOAL_CONFIRMATION_AUTHORIZED=true' \
  'I UNDERSTAND PMEM GOAL CHANGES DESTROY DATA AND REQUIRE REBOOT' \
  'stage.reviewed.sources' \
  'runner.ensure.privileged.session'; do
  require_contains "setup/cli/ipmctl.sh" "${marker}"
done

for marker in \
  "ipmctl_mode_effective in ['apply', 'validate', 'goal-plan', 'goal-apply']" \
  'ipmctl_facts_path: /etc/ansible/debian/facts/ipmctl.yml' \
  'Refuse Debian-packaged or foreign-repository ipmctl migration' \
  'Refuse unmanaged local ipmctl replacement' \
  'Fail closed on unsafe PMem goal prerequisites' \
  "ipmctl_mode_effective == 'goal-apply'" \
  'ipmctl_goal_confirmation_authorized | bool' \
  'Return machine-readable PMem goal-plan disposition' \
  'Apply pinned upstream Linux compatibility patch' \
  'Verify pinned upstream Linux compatibility patch application' \
  '"-DBUILDNUM={{ ipmctl_profile_policy.binary_version }}"' \
  'ipmctl_previous_facts.ipmctl.source.binary_version' \
  'ipmctl_previous_facts.ipmctl.source.os_patch_script' \
  'ipmctl_previous_facts.ipmctl.source.os_patch' \
  'ipmctl_profile_policy.binary_version in ipmctl_inventory.binary.version' \
  'namespace_deleted: false' \
  'pcd_deleted: false' \
  'firmware_changed: false' \
  'security_changed: false' \
  'reboot_performed: false'; do
  require_contains "ansible/cli/ipmctl.yml" "${marker}"
done

for marker in \
  'IPMCTL_BINARY_VERSION="03.00.00.0538"' \
  'IPMCTL_OS_PATCH="src/os/patches/0001-Ignore-STATIC_ASSERTs-and-NULL-define-for-os-and-ut-builds.patch"' \
  './updateedk.sh' \
  './patch_OS.sh' \
  'git apply --numstat' \
  'git apply --reverse --check' \
  '-DBUILDNUM="${IPMCTL_BINARY_VERSION}"' \
  "grep -R -Fq -- '-Werror' build/CMakeFiles" \
  'version_token' \
  'ldd "${TEST_ROOT}/install/bin/ipmctl"'; do
  require_contains "actions/test.ipmctl-source-build.sh" "${marker}"
done

for file in actions/test.ipmctl-source-build.sh ansible/cli/ipmctl.yml; do
  reject_contains "${file}" '-Wno-error'
done

update_line="$(grep -n -m1 'updateedk[.]sh' actions/test.ipmctl-source-build.sh | cut -d: -f1)"
patch_line="$(
  grep -n -m1 '^[[:space:]]*[.]/patch_OS[.]sh[[:space:]]*|' \
    actions/test.ipmctl-source-build.sh |
    cut -d: -f1
)"
cmake_line="$(grep -n -m1 'cmake -S' actions/test.ipmctl-source-build.sh | cut -d: -f1)"
if [[ -z "${update_line}" || -z "${patch_line}" || -z "${cmake_line}" ]] ||
  ((update_line >= patch_line || patch_line >= cmake_line)); then
  contract.error "ipmctl source build must run updateedk.sh, patch_OS.sh, then CMake"
fi

for prohibited in \
  'delete -pcd' \
  'delete -goal' \
  'delete -dimm' \
  'start -format' \
  'load -firmware' \
  'set -dimm' \
  'ndctl destroy-namespace' \
  'systemctl reboot' \
  '/sbin/reboot'; do
  reject_contains "ansible/cli/ipmctl.yml" "${prohibited}"
done

set +e
confirmation_trace="$(
  TEST_RUNNER="${ROOT}/setup/cli/ipmctl.sh" bash -c '
    source "${TEST_RUNNER}"
    FEATURE_MODE=goal-apply
    ANSIBLE_VENV_BIN=/usr/bin/true
    GOAL_PLAN_RESULT_PATH="$(mktemp)"
    runner.ensure.privileged.session() { return 0; }
    write.extra.vars.file() { :; }
    run.feature.playbook() { printf "no_op=false\n" > "${GOAL_PLAN_RESULT_PATH}"; }
    runner.confirm.exact() {
      printf "PROMPT=%s\nEXPECTED=%s\n" "$1" "$2"
      return 3
    }
    run.managed.mode
  ' 2>&1
)"
confirmation_status=$?
set -e
if [[ "${confirmation_status}" -ne 3 ]]; then
  contract.error "non-no-op goal-apply did not stop when exact confirmation was rejected"
fi
if [[ "${confirmation_trace}" != *"EXPECTED=I UNDERSTAND PMEM GOAL CHANGES DESTROY DATA AND REQUIRE REBOOT"* ]]; then
  contract.error "goal-apply did not pass the exact destructive confirmation phrase"
fi

set +e
noop_trace="$(
  TEST_RUNNER="${ROOT}/setup/cli/ipmctl.sh" bash -c '
    source "${TEST_RUNNER}"
    FEATURE_MODE=goal-apply
    ANSIBLE_VENV_BIN=/usr/bin/true
    GOAL_PLAN_RESULT_PATH="$(mktemp)"
    runner.ensure.privileged.session() { return 0; }
    write.extra.vars.file() { printf "WRITE:%s\n" "${FEATURE_MODE}"; }
    run.feature.playbook() {
      printf "RUN:%s\n" "${FEATURE_MODE}"
      [[ "${FEATURE_MODE}" != goal-plan ]] || printf "no_op=true\n" > "${GOAL_PLAN_RESULT_PATH}"
    }
    runner.confirm.exact() { printf "UNEXPECTED_CONFIRM\n"; return 90; }
    run.managed.mode
  ' 2>&1
)"
noop_status=$?
set -e
if [[ "${noop_status}" -ne 0 ]] || \
  [[ "${noop_trace}" != *"RUN:goal-plan"* ]] || \
  [[ "${noop_trace}" != *"RUN:validate"* ]] || \
  [[ "${noop_trace}" == *"UNEXPECTED_CONFIRM"* ]]; then
  contract.error "a settled no-op goal did not refresh facts without confirmation or mutation"
fi

require_contains "ansible/packages.yml" 'ipmctl_build:'
require_contains "ansible/install.packages.yml" '      - ipmctl_build'
require_contains "setup/cli/llm/host.sh" '--require-ipmctl'
require_contains "ansible/cli/llm/host.yml" 'llm_host_ipmctl_facts_path: /etc/ansible/debian/facts/ipmctl.yml'
require_contains "docs/cli/llm/host/readme.md" '/etc/ansible/debian/facts/ipmctl.yml'

if ! validate_yaml_file "${ROOT}/ansible/cli/ipmctl.yml"; then
  rc=1
fi
if ! validate_shell_payloads "${ROOT}/ansible/cli/ipmctl.yml"; then
  rc=1
fi

if [[ "${SHELL_ONLY}" -eq 0 ]]; then
  matrix="${ROOT}/ansible/files/ipmctl/compatibility-matrix.yml"
  profile_helper="${ROOT}/ansible/files/ipmctl/source-profile.py"
  inventory_helper="${ROOT}/ansible/files/ipmctl/ipmctl-inventory.py"
  fixture_base="${ROOT}/actions/fixtures/ipmctl/memory-mode"

  python3 "${profile_helper}" \
    --matrix "${matrix}" \
    --profile trixie-v03.00.00.0538 \
    --repository-url https://github.com/intel/ipmctl.git \
    --release v03.00.00.0538 \
    --commit a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url https://github.com/tianocore/edk2.git \
    --edk2-release edk2-stable202405 \
    --edk2-commit 3e722403cd16388a0e4044e705a2b34c841d76ca >/dev/null || rc=1

  if python3 "${profile_helper}" \
    --matrix "${matrix}" \
    --profile trixie-v03.00.00.0538 \
    --repository-url https://github.com/intel/ipmctl.git \
    --release v03.00.00.0538 \
    --commit a71f2fb \
    --edk2-repository-url https://github.com/tianocore/edk2.git \
    --edk2-release edk2-stable202405 \
    --edk2-commit 3e722403cd16388a0e4044e705a2b34c841d76ca >/dev/null 2>&1; then
    contract.error "a shortened ipmctl commit was accepted"
  fi

  snapshot="$(
    python3 "${inventory_helper}" --fixture-dir "${fixture_base}"
  )" || {
    contract.error "ipmctl Memory Mode fixture execution failed"
    snapshot=""
  }
  if [[ -n "${snapshot}" ]]; then
    python3 - "${snapshot}" <<'PY' || rc=1
import json
import sys

snapshot = json.loads(sys.argv[1])
assert snapshot["schema_version"] == 1
assert snapshot["hardware"]["socket_ids"] == [0, 1]
assert snapshot["hardware"]["topology_verified"] is True
assert snapshot["hardware"]["manageable"] is True
assert snapshot["hardware"]["healthy"] is True
assert snapshot["hardware"]["security_safe_for_goal"] is True
assert snapshot["memory_resources"]["current_mode"] == "memory-mode"
assert snapshot["memory_resources"]["memory_mode_verified"] is True
assert snapshot["pending_goal"]["present"] is False
assert snapshot["ndctl"]["namespace_count"] == 0
assert snapshot["readiness"]["goal_change_supported"] is True
PY
  fi

  for scenario in app-direct unsupported malformed namespaces pending-goal partial-failure; do
    snapshot="$(
      python3 "${inventory_helper}" \
        --fixture-dir "${ROOT}/actions/fixtures/ipmctl/${scenario}" \
        --fixture-base-dir "${fixture_base}"
    )" || {
      contract.error "ipmctl ${scenario} fixture execution failed"
      snapshot=""
    }
    [[ -n "${snapshot}" ]] || continue
    python3 - "${scenario}" "${snapshot}" <<'PY' || rc=1
import json
import sys

scenario = sys.argv[1]
snapshot = json.loads(sys.argv[2])
if scenario == "app-direct":
    assert snapshot["memory_resources"]["current_mode"] == "app-direct"
    assert snapshot["memory_resources"]["memory_mode_verified"] is False
elif scenario == "unsupported":
    assert snapshot["capabilities"]["platform_config_supported"] is False
    assert snapshot["readiness"]["goal_change_supported"] is False
elif scenario == "malformed":
    assert snapshot["hardware"]["present"] is False
    assert snapshot["readiness"]["inventory_ready"] is False
    assert snapshot["readiness"]["goal_change_supported"] is False
elif scenario == "namespaces":
    assert snapshot["ndctl"]["namespace_count"] == 1
elif scenario == "pending-goal":
    assert snapshot["pending_goal"]["present"] is True
    assert snapshot["readiness"]["settled"] is False
elif scenario == "partial-failure":
    assert snapshot["commands"]["topology"]["rc"] == 1
    assert snapshot["readiness"]["inventory_ready"] is False
PY
  done
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred Python fixtures and source verification to CI"
fi

resolve_remote_tag() {
  local repository="$1" release="$2" output="" direct="" peeled=""
  output="$(git ls-remote --tags "${repository}" "refs/tags/${release}" "refs/tags/${release}^{}")"
  direct="$(printf '%s\n' "${output}" | awk -v ref="refs/tags/${release}" '$2 == ref {print $1}')"
  peeled="$(printf '%s\n' "${output}" | awk -v ref="refs/tags/${release}^{}" '$2 == ref {print $1}')"
  printf '%s\n' "${peeled:-${direct}}"
}

if [[ "${SHELL_ONLY}" -eq 0 && "${NETWORK_VERIFY}" == 1 ]]; then
  actual_ipmctl="$(resolve_remote_tag https://github.com/intel/ipmctl.git v03.00.00.0538)"
  [[ "${actual_ipmctl}" == a71f2fb1c90dd07f9862b71c789881132193e8f9 ]] ||
    contract.error "ipmctl reviewed tag changed: ${actual_ipmctl}"
  actual_edk2="$(resolve_remote_tag https://github.com/tianocore/edk2.git edk2-stable202405)"
  [[ "${actual_edk2}" == 3e722403cd16388a0e4044e705a2b34c841d76ca ]] ||
    contract.error "edk2 reviewed tag changed: ${actual_edk2}"
else
  echo "[${ACTION_LABEL}] source network verification deferred to GitHub Actions"
fi

exit "${rc}"
