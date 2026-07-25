#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.nvidia-contract"
rc=0
SHELL_ONLY=0

case "${1:-}" in
  "") ;;
  --shell-only) SHELL_ONLY=1 ;;
  *)
    echo "[${ACTION_LABEL}][error] usage: bash actions/test.nvidia-contract.sh [--shell-only]" >&2
    exit 64
    ;;
esac
if (($# > 1)); then
  echo "[${ACTION_LABEL}][error] usage: bash actions/test.nvidia-contract.sh [--shell-only]" >&2
  exit 64
fi

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking NVIDIA runner, playbook, and fact contracts..."

require_shell_syntax "setup/cli/nvidia.sh"
if ! grep -Fxq 'ansible-core==2.20.5' "${ROOT}/actions/requirements.validation.txt" || \
  ! grep -Fxq 'PyYAML==6.0.2' "${ROOT}/actions/requirements.validation.txt"; then
  contract.error "CI validation dependencies must pin Ansible Core and PyYAML"
fi
if ! awk '
  /name: Install pinned runtime validation dependencies/ { dependencies = NR }
  /name: Validate runtime contract/ { validation = NR }
  END { exit !(dependencies > 0 && validation > dependencies) }
' "${ROOT}/.github/workflows/www.pages.yml"; then
  contract.error "pinned validation dependencies must be installed before runtime validation"
fi

nvidia_runtime_manifest="$(
  sed -n '/^RUNTIME_SUPPORT_REFS=(/,/^)/p' "${ROOT}/setup/cli/nvidia.sh"
)"
for reference in \
  '"packages.yml"' \
  '"tasks/nvidia.normalize-observations.yml"'; do
  if [[ "${nvidia_runtime_manifest}" != *"${reference}"* ]]; then
    contract.error "NVIDIA runtime manifest is missing ${reference}"
  fi
done
require_contains "setup/cli/nvidia.sh" 'runner.stage.ansible.feature'
require_contains "setup/runner.common.sh" 'runner.verify.manifest'
require_contains "ansible/cli/nvidia.yml" 'file: ../packages.yml'
require_regex "ansible/packages.yml" '^[[:space:]]*nvidia_runtime_support:'

for marker in \
  'nvidia_llm_shell_path' \
  'export CUDA_HOME=' \
  'Reject skipped live validation in validate mode' \
  'Restrict persisted-policy refresh to NVIDIA validate mode' \
  'Check the package-managed CUDA runtime header' \
  'Determine CUDA runtime header readiness' \
  'Normalize NVIDIA observations before fact persistence' \
  'Persist NVIDIA readiness facts' \
  'Fail NVIDIA validation when requested live prerequisites are unavailable' \
  'ansible.builtin.include_tasks: ../tasks/nvidia.normalize-observations.yml' \
  'nvidia_smi_rc:' \
  'nvcc_rc:' \
  'runtime_header_ready:' \
  'validation_policy:' \
  'nvidia_validate_from_facts:'; do
  require_contains "ansible/cli/nvidia.yml" "${marker}"
done
reject_contains "ansible/cli/nvidia.yml" 'LD_LIBRARY_PATH'

set +e
bash "${ROOT}/setup/cli/nvidia.sh" validate --skip-live-validate >/dev/null 2>&1
skip_validate_status=$?
set -e
if [[ "${skip_validate_status}" -ne 64 ]]; then
  contract.error "NVIDIA validate must reject --skip-live-validate before staging or host mutation"
fi

if ! awk '
  /name: Check the package-managed CUDA runtime header/ { header = NR }
  /name: Normalize NVIDIA observations before fact persistence/ { normalize = NR }
  /name: Persist NVIDIA readiness facts/ { facts = NR }
  END { exit !(header > 0 && normalize > header && facts > normalize) }
' "${ROOT}/ansible/cli/nvidia.yml"; then
  contract.error "NVIDIA runtime-header, normalization, and fact-persistence tasks are out of order"
fi

for marker in \
  'nvidia_driver_candidate:' \
  'skipped: true' \
  'candidate_package_version: 595.71.05-1' \
  "nvidia_fact_driver_candidate_package_version == ''" \
  "nvidia_regression_smi_rc | type_debug == 'int'" \
  "nvidia_regression_nvcc_rc | type_debug == 'int'" \
  'schema_version: 1'; do
  require_contains "actions/fixtures/nvidia.register-normalization.yml" "${marker}"
done
if grep -RFq -- "(nvidia_driver_candidate | default({'stdout': ''})).stdout" "${ROOT}/ansible"; then
  contract.error "unsafe NVIDIA candidate stdout dereference has returned"
fi

if [[ "${SHELL_ONLY}" -eq 0 ]]; then
  if ! validate_yaml_file "${ROOT}/ansible/tasks/nvidia.normalize-observations.yml"; then
    rc=1
  fi
  if ! validate_yaml_file "${ROOT}/actions/fixtures/nvidia.register-normalization.yml"; then
    rc=1
  fi
  require_shell_syntax "actions/test.nvidia-facts.sh"
  run_contract_action "actions/test.nvidia-facts.sh"
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred YAML and Ansible fixture checks to CI"
fi

exit "${rc}"
