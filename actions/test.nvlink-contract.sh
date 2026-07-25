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

echo "[${ACTION_LABEL}] checking NVLink runner, ownership, and validation contracts..."

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
  '"files/nvlink/nvidia-cuda-smoke.cu"' \
  '"files/nvlink/nvidia-p2p-verify.cu"' \
  '"files/nvlink/nvidia-topology-parser.py"'; do
  require_contains "setup/cli/nvlink.sh" "${reference}"
done
require_contains "setup/cli/nvlink.sh" 'runner.stage.ansible.feature'

for marker in \
  'import_playbook: nvidia.yml' \
  'nvidia_mode: validate' \
  'nvidia_validate_from_facts: true' \
  'Initialize immutable NVLink run identifier' \
  'Initialize immutable NVLink log directory' \
  'Create managed NVLink directories' \
  'Record CUDA helper compilation output' \
  'Reread refreshed NVIDIA installation facts without taking ownership' \
  'Require the shared GPU snapshot refreshed by NVIDIA validation' \
  'Read the refreshed shared GPU snapshot' \
  'Validate the shared GPU snapshot contract for NVLink' \
  'Check live NVIDIA and CUDA prerequisite executables' \
  'Normalize the NVIDIA prerequisite fact contract' \
  'Verify NVIDIA facts agree with live prerequisite state'; do
  require_contains "ansible/cli/nvlink.yml" "${marker}"
done
if ! awk '
  /import_playbook: nvidia\.yml/ { imported = NR }
  /nvidia_mode: validate/ { validate = NR }
  /nvidia_validate_from_facts: true/ { refresh = NR }
  /name: Debian standalone CUDA, NVLink, and P2P validation/ { nvlink_play = NR }
  /name: Reread refreshed NVIDIA installation facts without taking ownership/ { reread = NR }
  /name: Check live NVIDIA and CUDA prerequisite executables/ { live = NR }
  /name: Verify NVIDIA facts agree with live prerequisite state/ { contract = NR }
  END {
    valid = imported > 0 && validate > imported && refresh > imported
    valid = valid && nvlink_play > refresh && reread > nvlink_play
    valid = valid && live > reread && contract > live
    if (!valid) {
      exit 1
    }
  }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink must refresh, reread, and verify NVIDIA-owned facts in order"
fi

if awk '
  /^  vars:$/ { in_vars = 1; next }
  /^  pre_tasks:$/ { in_vars = 0 }
  in_vars && /now\(/ { dynamic_run_path = 1 }
  END { exit !dynamic_run_path }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink run paths must not evaluate now() from playbook-level vars"
fi
if ! awk '
  /name: Initialize immutable NVLink run identifier/ { run_id = NR }
  /name: Initialize immutable NVLink log directory/ { log_dir = NR }
  /name: Create managed NVLink directories/ { directories = NR }
  /name: Record CUDA helper compilation output/ { compilation_log = NR }
  END { exit !(run_id > 0 && log_dir > run_id && directories > log_dir && compilation_log > directories) }
' "${ROOT}/ansible/cli/nvlink.yml"; then
  contract.error "NVLink must initialize one immutable log directory before writing run artifacts"
fi

for marker in \
  "nvlink_nvidia_facts_path == '/etc/ansible/debian/facts/nvidia.yml'" \
  "nvlink_facts_path == '/etc/ansible/debian/facts/nvlink.yml'" \
  'nvlink_nvidia_facts_path != nvlink_facts_path' \
  'nvlink_nvidia_schema_version' \
  'nvlink_fact_nvidia_smi_ready' \
  'nvlink_fact_nvcc_ready' \
  'nvlink_fact_runtime_header_ready'; do
  require_contains "ansible/cli/nvlink.yml" "${marker}"
done

for marker in \
  'llm-nvidia-validated.sh' \
  'nvidia-cuda-smoke' \
  'nvidia-p2p-verify' \
  'nvidia-topology-parser.py' \
  'NV4' \
  'CUDA_VISIBLE_DEVICES' \
  'command -v nvidia-smi' \
  'nvidia_smi_path' \
  '"${nvidia_smi_path}" >/dev/null' \
  'nvlink_gpu_facts_path' \
  'mig_enabled' \
  '--source-label' \
  '--destination-label'; do
  require_contains "ansible/cli/nvlink.yml" "${marker}"
done
reject_contains "ansible/cli/nvlink.yml" 'test -x nvidia-smi'
reject_contains "ansible/cli/nvlink.yml" '--source-index'
reject_contains "ansible/cli/nvlink.yml" '--destination-index'
reject_contains "ansible/cli/nvlink.yml" 'Collect live physical GPU inventory and resolve UUID/PCI selection'

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
  contract.error "NVLink must not write shared GPU facts"
fi
reject_regex "ansible/cli/nvlink.yml" 'nvidia-driver|cuda-toolkit|cuda-keyring|grub|mokutil|update-initramfs|LD_LIBRARY_PATH'
reject_regex "ansible/cli/nvlink.yml" 'GGML_CUDA_P2P=|GGML_CUDA_ENABLE_UNIFIED_MEMORY='

nvlink_validation_packages="$(
  awk '
    /^  nvlink_validation_support:$/ { in_group = 1; next }
    in_group && /^  [A-Za-z0-9_]+:$/ { exit }
    in_group { print }
  ' "${ROOT}/ansible/packages.yml"
)"
for package in build-essential cmake ninja-build git jq pciutils; do
  if ! grep -Eq "^[[:space:]]*-[[:space:]]+${package}$" <<< "${nvlink_validation_packages}"; then
    contract.error "nvlink_validation_support is missing package ${package}"
  fi
done
nvlink_bandwidth_packages="$(
  awk '
    /^  nvlink_bandwidth_optional:$/ { in_group = 1; next }
    in_group && /^  [A-Za-z0-9_]+:$/ { exit }
    in_group { print }
  ' "${ROOT}/ansible/packages.yml"
)"
if ! grep -Eq '^[[:space:]]*-[[:space:]]+libboost-program-options-dev$' <<< "${nvlink_bandwidth_packages}"; then
  contract.error "nvlink_bandwidth_optional is missing libboost-program-options-dev"
fi
if grep -qx 'cli/nvlink.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  contract.error "baseline playlist must not include cli/nvlink.yml"
fi

for marker in cudaGetDeviceCount cudaDeviceSynchronize; do
  require_contains "ansible/files/nvlink/nvidia-cuda-smoke.cu" "${marker}"
done
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
