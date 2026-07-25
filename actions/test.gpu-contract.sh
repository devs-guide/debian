#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.gpu-contract"
rc=0
SHELL_ONLY=0

case "${1:-}" in
  "") ;;
  --shell-only) SHELL_ONLY=1 ;;
  *)
    echo "[${ACTION_LABEL}][error] usage: bash actions/test.gpu-contract.sh [--shell-only]" >&2
    exit 64
    ;;
esac

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking shared GPU inventory and topology contracts..."

require_shell_syntax "setup/cli/gpu.sh"
for marker in \
  'FEATURE_PLAYBOOKS=("cli/gpu.yml")' \
  'tasks/gpu.inventory.yml' \
  'files/gpu/gpu-inventory.py' \
  'files/gpu/nvidia_topology.py' \
  'runner.stage.ansible.feature' \
  'runner.ensure.privileged.session'; do
  require_contains "setup/cli/gpu.sh" "${marker}"
done

for marker in \
  'shared GPU hardware and runtime snapshot' \
  'gpu_facts_path: /etc/ansible/debian/facts/gpu.yml' \
  'gpu-inventory.py' \
  'The shared GPU inventory supports apply and validate only.'; do
  require_contains "ansible/cli/gpu.yml" "${marker}"
done

for marker in \
  'Collect the shared GPU hardware and runtime snapshot' \
  'Validate live NVIDIA topology before shared fact persistence' \
  'Persist the shared GPU snapshot' \
  '/etc/ansible/debian/facts/gpu.yml' \
  'expected_labels' \
  'header_labels' \
  'row_labels' \
  'gpu_inventory_helper_path'; do
  require_contains "ansible/tasks/gpu.inventory.yml" "${marker}"
done

gpu_mapping_gate_line="$(
  awk '/^- name: Validate live NVIDIA topology before shared fact persistence/ { print NR; exit }' \
    "${ROOT}/ansible/tasks/gpu.inventory.yml"
)"
gpu_persist_line="$(
  awk '/^- name: Persist the shared GPU snapshot/ { print NR; exit }' \
    "${ROOT}/ansible/tasks/gpu.inventory.yml"
)"
if [[ -z "${gpu_mapping_gate_line}" || -z "${gpu_persist_line}" || "${gpu_mapping_gate_line}" -ge "${gpu_persist_line}" ]]; then
  contract.error "live NVIDIA topology validation must run before shared GPU fact persistence"
fi

for marker in \
  'canonical_pci' \
  'map_topology_labels' \
  'label_mapping' \
  'missing_labels' \
  'topology_label' \
  'pci_bus_aliases' \
  'requested_vendor' \
  'nvidia-smi' \
  'parse_topology'; do
  require_contains "ansible/files/gpu/gpu-inventory.py" "${marker}"
done
for marker in \
  'def parse_topology' \
  'def pair_result' \
  'def normalize_topology_line' \
  'topology header and route rows disagree' \
  'row_labels' \
  'normalized-topology-header' \
  'discovered_labels'; do
  require_contains "ansible/files/gpu/nvidia_topology.py" "${marker}"
done
reject_contains "ansible/files/gpu/nvidia_topology.py" 'if source_label not in labels:'
for marker in --source-label --destination-label; do
  require_contains "ansible/files/nvlink/nvidia-topology-parser.py" "${marker}"
done
reject_contains "ansible/files/nvlink/nvidia-topology-parser.py" '--source-index'
reject_contains "ansible/files/nvlink/nvidia-topology-parser.py" '--destination-index'

for consumer in ansible/cli/nvidia.yml ansible/cli/nvlink.yml; do
  if awk '
    /ansible\.builtin\.(copy|template|file|lineinfile|blockinfile|assemble):/ { writer = 1; next }
    /^[[:space:]]*-[[:space:]]+name:/ { writer = 0 }
    writer && /[[:space:]](dest|path): "\{\{ (nvidia|nvlink)_gpu_facts_path \}\}"/ { bad = 1 }
    END { exit !bad }
  ' "${ROOT}/${consumer}"; then
    contract.error "${consumer} must consume, not write, shared GPU facts"
  fi
done

if [[ "${SHELL_ONLY}" -eq 0 ]]; then
  fixture="${ROOT}/actions/fixtures/nvidia-topology.gpu0-gpu1.txt"
  result="$(PYTHONPATH="${ROOT}/ansible/files/gpu" python3 "${ROOT}/ansible/files/nvlink/nvidia-topology-parser.py" \
    --topology "${fixture}" --source-label GPU0 --destination-label GPU1)" || {
    contract.error "exact NVIDIA topology fixture must parse successfully"
    result=""
  }
  [[ "${result}" == *'"route": "NV4"'* ]] || contract.error "GPU0 -> GPU1 must resolve to NV4 from the exact topology fixture"
  reordered_fixture="${ROOT}/actions/fixtures/nvidia-topology.gpu1-gpu0.txt"
  reordered_result="$(PYTHONPATH="${ROOT}/ansible/files/gpu" python3 "${ROOT}/ansible/files/nvlink/nvidia-topology-parser.py" \
    --topology "${reordered_fixture}" --source-label GPU0 --destination-label GPU1)" || {
    contract.error "reordered NVIDIA topology fixture must parse successfully"
    reordered_result=""
  }
  [[ "${reordered_result}" == *'"route": "NV4"'* ]] || contract.error "GPU0 -> GPU1 must resolve from a reordered topology header"
  mapping_result="$(PYTHONPATH="${ROOT}/ansible/files/gpu" python3 - "${fixture}" "${ROOT}/ansible/files/gpu/gpu-inventory.py" <<'PY'
import json
import importlib.util
import sys
from pathlib import Path

from nvidia_topology import TopologyParseError, pair_result, parse_topology

module_path = Path(sys.argv[2]).resolve()
spec = importlib.util.spec_from_file_location("gpu_inventory", module_path)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load GPU inventory helper: {module_path}")
gpu_inventory = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gpu_inventory
spec.loader.exec_module(gpu_inventory)

fixture_text = Path(sys.argv[1]).read_text()
topology = parse_topology(fixture_text)
rows = [{"index": 0, "topology_label": ""}, {"index": 1, "topology_label": ""}]
mapping = gpu_inventory.map_topology_labels(rows, topology)

assert topology["labels"] == ["GPU0", "GPU1"]
assert topology["row_labels"] == ["GPU0", "GPU1"]
assert topology["label_source"] == "normalized-topology-header"
assert pair_result(fixture_text, "GPU0", "GPU1")["route"] == "NV4"
assert mapping["complete"] is True
assert mapping["missing_labels"] == []
assert mapping["unexpected_labels"] == []
assert mapping["expected_labels"] == ["GPU0", "GPU1"]
assert mapping["resolved_labels"] == ["GPU0", "GPU1"]
assert mapping["header_labels"] == ["GPU0", "GPU1"]
assert mapping["row_labels"] == ["GPU0", "GPU1"]

normalized_variants = {
    "bom": fixture_text.replace("GPU0", "\ufeffGPU0", 1),
    "ansi": fixture_text.replace("GPU0", "\x1b[31mGPU0\x1b[0m", 1),
    "control": fixture_text.replace("GPU0", "GPU\x000", 1),
}
for name, variant in normalized_variants.items():
    parsed_variant = parse_topology(variant)
    assert parsed_variant["labels"] == ["GPU0", "GPU1"], name
    assert pair_result(variant, "GPU0", "GPU1")["route"] == "NV4", name

def must_fail(name, malformed):
    try:
        parse_topology(malformed)
    except TopologyParseError:
        return
    raise AssertionError(f"{name} topology unexpectedly parsed")

header = "\tGPU0\tGPU1\tCPU Affinity\tNUMA Affinity\tGPU NUMA ID"
must_fail("missing header label", fixture_text.replace(header, header.replace("GPU0", "GPU9"), 1))
must_fail("extra header label", fixture_text.replace(header, header.replace("CPU", "GPU2\tCPU"), 1))
must_fail("duplicate header label", fixture_text.replace(header, header.replace("GPU1", "GPU0"), 1))
must_fail("malformed header label", fixture_text.replace(header, header.replace("GPU0", "GPU-A"), 1))
must_fail("multiple headers", fixture_text.replace(header, f"{header}\n{header}", 1))

fixture_lines = fixture_text.splitlines()
gpu0_row = next(line for line in fixture_lines if line.startswith("GPU0"))
must_fail("missing route row", fixture_text.replace(f"{gpu0_row}\n", "", 1))
must_fail("duplicate route row", fixture_text.replace(gpu0_row, f"{gpu0_row}\n{gpu0_row}", 1))

incomplete_rows = [{"index": 0, "topology_label": ""}, {"index": 2, "topology_label": ""}]
incomplete_mapping = gpu_inventory.map_topology_labels(incomplete_rows, topology)
assert incomplete_mapping["complete"] is False
assert incomplete_mapping["missing_labels"] == ["GPU2"]
assert incomplete_mapping["unexpected_labels"] == ["GPU1"]

print(json.dumps({"mapping": mapping, "rows": rows, "normalization_cases": sorted(normalized_variants)}, sort_keys=True))
PY
)" || {
    contract.error "shared GPU topology labels must map from the same topology fixture"
    mapping_result=""
  }
  [[ "${mapping_result}" == *'"complete": true'* ]] || contract.error "GPU0/GPU1 topology label mapping must be complete"
  [[ "${mapping_result}" == *'"header_labels": ["GPU0", "GPU1"]'* ]] || contract.error "topology header labels must match runtime indices"
  [[ "${mapping_result}" == *'"row_labels": ["GPU0", "GPU1"]'* ]] || contract.error "topology route-row labels must match runtime indices"
  [[ "${mapping_result}" == *'"topology_label": "GPU0"'* ]] || contract.error "GPU index 0 must map to topology label GPU0"
  [[ "${mapping_result}" == *'"topology_label": "GPU1"'* ]] || contract.error "GPU index 1 must map to topology label GPU1"
  if PYTHONPATH="${ROOT}/ansible/files/gpu" python3 "${ROOT}/ansible/files/nvlink/nvidia-topology-parser.py" \
    --topology "${fixture}" --source-label GPU0 --destination-label GPU9 >/dev/null 2>&1; then
    contract.error "unknown topology labels must fail closed"
  fi
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred Python fixture execution to CI"
fi

exit "${rc}"
