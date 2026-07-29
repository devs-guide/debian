#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.llm-host-contract"
rc=0
SHELL_ONLY=0

case "${1:-}" in
  "") ;;
  --shell-only) SHELL_ONLY=1 ;;
  *)
    echo "[${ACTION_LABEL}][error] usage: bash actions/test.llm-host-contract.sh [--shell-only]" >&2
    exit 64
    ;;
esac

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking shared LLM host-readiness contracts..."

for file in \
  setup/cli/llm/host.sh \
  ansible/cli/llm/host.yml \
  ansible/files/llm/host-inventory.py \
  docs/cli/llm/host/readme.md; do
  require_file "${file}"
done

require_shell_syntax "setup/cli/llm/host.sh"
for marker in \
  'LOCAL_RUNNER_HELPER="../../runner.common.sh"' \
  'FEATURE_PLAYBOOKS=("install.packages.yml" "cli/llm/host.yml")' \
  'files/llm/host-inventory.py' \
  'runner.prepare.ansible.feature' \
  'runner.ensure.privileged.session' \
  'runner.ensure.local.ansible' \
  '--profile=generic|icelake-pmem-dual-3090' \
  '--require-memory-mode' \
  '--require-ipmctl' \
  '--require-nvidia' \
  '--require-nvlink' \
  '--require-p2p' \
  '--install-support-packages' \
  '--no-install-support-packages'; do
  require_contains "setup/cli/llm/host.sh" "${marker}"
done

if bash "${ROOT}/setup/cli/llm/host.sh" apply --require-p2p >/dev/null 2>&1; then
  contract.error "standalone --require-p2p must fail before staging or host mutation"
elif [[ "$?" -ne 64 ]]; then
  contract.error "invalid P2P/NVLink dependency must exit 64"
fi

for marker in \
  'llm_host_facts_path: /etc/ansible/debian/facts/llm-host.yml' \
  'llm_host_env_path: /etc/ansible/debian/env/llm-host.sh' \
  'Collect the shared LLM host hardware snapshot' \
  'Validate required NVIDIA producer contracts' \
  'Validate required NVLink producer contract' \
  'Validate required directed P2P evidence' \
  'Validate required ipmctl producer contract' \
  'Verify live ipmctl has no pending PMem goal' \
  'Require live ipmctl identity and settled goal state' \
  '/etc/ansible/debian/facts/ipmctl.yml' \
  'producers:' \
  'ipmctl:' \
  'Read live NVIDIA PCI NUMA affinity' \
  'numa_affinity:' \
  'Create only missing managed LLM directories' \
  'not item.stat.exists' \
  'existing_directory_metadata_preserved: true' \
  'recursive_ownership_changes: false' \
  'model_downloaded: false' \
  'runtime_installed: false'; do
  require_contains "ansible/cli/llm/host.yml" "${marker}"
done

for prohibited in \
  swapoff \
  'sysctl -w' \
  'cpupower frequency-set' \
  update-grub \
  grub-mkconfig \
  'chown -R' \
  ktransformers \
  huggingface-cli \
  'git clone'; do
  reject_contains "ansible/cli/llm/host.yml" "${prohibited}"
done

for marker in \
  'physical_cpu_selection' \
  'selected_cpu_mask' \
  'excluded_smt_siblings' \
  'collect_numa' \
  'collect_memory_mode' \
  '"verified"' \
  '"consistent"' \
  '"unknown"' \
  '--fixture-dir'; do
  require_contains "ansible/files/llm/host-inventory.py" "${marker}"
done

require_contains "ansible/packages.yml" 'llm_host_support:'
require_contains "ansible/install.packages.yml" '      - llm_host_support'
if grep -qx 'cli/llm/host.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  contract.error "LLM host readiness must remain opt-in and outside the baseline playlist"
fi

if ! validate_yaml_file "${ROOT}/ansible/cli/llm/host.yml"; then
  rc=1
fi
if ! validate_shell_payloads "${ROOT}/ansible/cli/llm/host.yml"; then
  rc=1
fi

if [[ "${SHELL_ONLY}" -eq 0 ]]; then
  snapshot="$(
    python3 "${ROOT}/ansible/files/llm/host-inventory.py" \
      --fixture-dir "${ROOT}/actions/fixtures/llm-host"
  )" || {
    contract.error "LLM host inventory fixture execution failed"
    snapshot=""
  }
  if [[ -n "${snapshot}" ]]; then
    python3 - "${snapshot}" <<'PY' || rc=1
import json
import sys

snapshot = json.loads(sys.argv[1])
assert snapshot["schema_version"] == 1
assert snapshot["cpu"]["vendor_id"] == "GenuineIntel"
assert "8351N" in snapshot["cpu"]["model_name"]
assert snapshot["cpu"]["logical_count"] == 8
assert snapshot["cpu"]["physical_core_count"] == 4
assert snapshot["cpu"]["selected_logical_cpus"] == [0, 2, 4, 6]
assert snapshot["cpu"]["excluded_smt_siblings"] == [1, 3, 5, 7]
assert snapshot["cpu"]["selected_cpu_list"] == "0,2,4,6"
assert snapshot["cpu"]["selected_cpu_mask"] == "0x55"
assert snapshot["memory"]["available_kib"] == 402653184
assert snapshot["numa"]["count"] == 2
assert snapshot["numa"]["nodes"][0]["distance"] == [10, 20]
assert snapshot["numa"]["nodes"][1]["distance"] == [20, 10]
assert snapshot["memory_mode"]["classification"] == "verified"
PY
  fi
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred Python fixture execution to CI"
fi

exit "${rc}"
