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
  'Persist the shared GPU snapshot' \
  '/etc/ansible/debian/facts/gpu.yml' \
  'gpu_inventory_helper_path'; do
  require_contains "ansible/tasks/gpu.inventory.yml" "${marker}"
done

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
  'topology output is missing route rows' \
  'discovered_labels'; do
  require_contains "ansible/files/gpu/nvidia_topology.py" "${marker}"
done
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

from nvidia_topology import parse_topology

module_path = Path(sys.argv[2]).resolve()
spec = importlib.util.spec_from_file_location("gpu_inventory", module_path)
if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load GPU inventory helper: {module_path}")
gpu_inventory = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gpu_inventory
spec.loader.exec_module(gpu_inventory)

topology = parse_topology(Path(sys.argv[1]).read_text())
rows = [{"index": 0, "topology_label": ""}, {"index": 1, "topology_label": ""}]
mapping = gpu_inventory.map_topology_labels(rows, topology)
print(json.dumps({"mapping": mapping, "rows": rows}, sort_keys=True))
PY
)" || {
    contract.error "shared GPU topology labels must map from the same topology fixture"
    mapping_result=""
  }
  [[ "${mapping_result}" == *'"complete": true'* ]] || contract.error "GPU0/GPU1 topology label mapping must be complete"
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
