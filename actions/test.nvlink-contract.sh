#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.nvlink-contract"
rc=0
SHELL_ONLY=0

case "${1:-}" in
  "") ;;
  --shell-only) SHELL_ONLY=1 ;;
  *)
    echo "[${ACTION_LABEL}][error] usage: bash actions/test.nvlink-contract.sh [--shell-only]" >&2
    exit 64
    ;;
esac
if (($# > 1)); then
  echo "[${ACTION_LABEL}][error] usage: bash actions/test.nvlink-contract.sh [--shell-only]" >&2
  exit 64
fi

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking lean NVLink runner and fact contracts..."

require_shell_syntax "setup/cli/nvlink.sh"

set +e
bash "${ROOT}/setup/cli/nvlink.sh" apply --strict-p2p >/dev/null 2>&1
strict_p2p_status=$?
set -e
if [[ "${strict_p2p_status}" -ne 64 ]]; then
  contract.error "NVLink apply must reject --strict-p2p without --run-p2p-test before host activity"
fi

for reference in \
  '"cli/nvidia.yml"' \
  '"cli/nvlink.yml"' \
  '"packages.yml"' \
  '"tasks/gpu.inventory.yml"' \
  '"tasks/nvidia.normalize-observations.yml"' \
  '"files/gpu/gpu-inventory.py"' \
  '"files/gpu/nvidia_topology.py"' \
  '"files/nvlink/nvidia-p2p-verify.cu"'; do
  require_contains "setup/cli/nvlink.sh" "${reference}"
done

for marker in \
  'runner.source.release.common' \
  'runner.prepare.ansible.feature' \
  'runner.ensure.local.ansible' \
  'runner.run.ansible.playbooks' \
  'runner.report.command' \
  'runner.report.text'; do
  require_contains "setup/cli/nvlink.sh" "${marker}"
done

for marker in \
  'import_playbook: nvidia.yml' \
  'nvidia_mode: validate' \
  'nvidia_validate_from_facts: true' \
  'Initialize immutable NVLink run identifier' \
  'Initialize immutable NVLink log directory' \
  'Validate the shared GPU snapshot contract for NVLink' \
  'Read selected pair route from the shared GPU topology matrix' \
  'Query positive NVLink bandwidth evidence for each selected GPU' \
  'Record per-GPU NVLink bandwidth evidence' \
  "select('greaterthan', 0.0)" \
  'Run opt-in directed CUDA P2P validation' \
  'Enforce requested P2P correctness' \
  'schema_version: 2' \
  'all_commands_succeeded' \
  'all_selected_active' \
  'nvlink_ready' \
  'p2p_ready'; do
  require_contains "ansible/cli/nvlink.yml" "${marker}"
done

for obsolete in \
  'topo -p2p' \
  'official_samples' \
  'cuda_samples' \
  'nvbandwidth' \
  'artifact_hash' \
  'smoke_binary_sha256' \
  'p2p_matrix' \
  'nvlink_transport_ready'; do
  reject_contains "ansible/cli/nvlink.yml" "${obsolete}"
done
require_contains "ansible/cli/nvlink.yml" 'Remove superseded NVLink-owned artifacts'
for retired_source in \
  'src: ../files/nvlink/nvidia-cuda-smoke.cu' \
  'src: ../files/nvlink/nvidia-topology-parser.py'; do
  reject_contains "ansible/cli/nvlink.yml" "${retired_source}"
done

for obsolete in \
  '--official-samples' \
  '--cuda-samples-path' \
  '--cuda-samples-tag' \
  '--strict-official-samples' \
  '--run-nvbandwidth' \
  '--nvbandwidth-path' \
  '--nvbandwidth-ref' \
  'DEBIAN_NVLINK_OFFICIAL_SAMPLES' \
  'DEBIAN_NVLINK_RUN_NVBANDWIDTH'; do
  reject_contains "setup/cli/nvlink.sh" "${obsolete}"
done

reject_contains "ansible/cli/nvlink.yml" 'test -x nvidia-smi'
reject_contains "ansible/cli/nvlink.yml" '--source-index'
reject_contains "ansible/cli/nvlink.yml" '--destination-index'
reject_regex "ansible/cli/nvlink.yml" 'rates_gbps:.*14[.]062'
reject_regex "ansible/cli/nvlink.yml" 'minimum[_ -]?(rate|bandwidth)|bandwidth[_ -]?floor'
reject_regex "ansible/cli/nvlink.yml" 'nvidia-driver|cuda-toolkit|cuda-keyring|grub|mokutil|update-initramfs|LD_LIBRARY_PATH'

if ! awk '
  /name: Read selected pair route from the shared GPU topology matrix/ { route = NR }
  /name: Query positive NVLink bandwidth evidence for each selected GPU/ { status = NR }
  /name: Run opt-in directed CUDA P2P validation/ { p2p = NR }
  /name: Persist compact NVLink validation facts/ { facts = NR }
  END { exit !(route > 0 && status > route && p2p > status && facts > p2p) }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink must resolve shared topology and status before optional P2P and fact persistence"
fi

if awk '
  /ansible\.builtin\.(copy|template|file|lineinfile|blockinfile|assemble):/ { writer = 1; next }
  /^[[:space:]]*-[[:space:]]+name:/ { writer = 0 }
  writer && /[[:space:]](dest|path): "\{\{ nvlink_nvidia_facts_path \}\}"/ { bad = 1 }
  END { exit !bad }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink must not write NVIDIA-owned facts"
fi
if awk '
  /ansible\.builtin\.(copy|template|file|lineinfile|blockinfile|assemble):/ { writer = 1; next }
  /^[[:space:]]*-[[:space:]]+name:/ { writer = 0 }
  writer && /[[:space:]](dest|path): "\{\{ nvlink_gpu_facts_path \}\}"/ { bad = 1 }
  END { exit !bad }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink must consume, not write, shared GPU facts"
fi

nvlink_validation_packages="$(
  awk '
    /^  nvlink_validation_support:$/ { in_group = 1; next }
    in_group && /^  [A-Za-z0-9_]+:$/ { exit }
    in_group { print }
  ' "${ROOT}/ansible/packages.yml"
)"
if ! grep -Eq '^[[:space:]]*-[[:space:]]+build-essential$' <<< "${nvlink_validation_packages}"; then
  contract.error "nvlink_validation_support must contain build-essential"
fi
for package in cmake ninja-build git jq pciutils libboost-program-options-dev; do
  if grep -Eq "^[[:space:]]*-[[:space:]]+${package}$" <<< "${nvlink_validation_packages}"; then
    contract.error "nvlink_validation_support retains superseded package ${package}"
  fi
done
reject_contains "ansible/packages.yml" 'nvlink_bandwidth_optional:'

if grep -qx 'cli/nvlink.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  contract.error "baseline playlist must not include cli/nvlink.yml"
fi

for marker in cudaDeviceCanAccessPeer cudaMemcpyPeerAsync; do
  require_contains "ansible/files/nvlink/nvidia-p2p-verify.cu" "${marker}"
done

if [[ "${SHELL_ONLY}" -eq 0 ]]; then
  if ! validate_yaml_file "${ROOT}/ansible/cli/nvlink.yml"; then
    rc=1
  fi
  if ! validate_shell_payloads "${ROOT}/ansible/cli/nvlink.yml"; then
    rc=1
  fi
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred YAML and embedded-shell parsing to CI"
fi

exit "${rc}"
