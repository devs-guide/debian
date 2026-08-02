#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.ipmctl-contract"
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

echo "[${ACTION_LABEL}] checking the pinned Debian 13 ipmctl installer..."

for file in \
  setup/cli/ipmctl.sh \
  ansible/cli/ipmctl.yml \
  ansible/files/ipmctl/apply-patch.yml \
  ansible/files/ipmctl/patches/README.md \
  ansible/files/ipmctl/patches/0001-edk2-stable202511-host-os-build.patch \
  ansible/files/ipmctl/patches/0002-ipmctl-disable-c-release-werror.patch \
  ansible/files/ipmctl/patches/0003-ipmctl-remove-pie-from-shared-linker-flags.patch \
  docs/cli/ipmctl/readme.md; do
  require_file "${file}"
done

for removed in \
  actions/test.ipmctl-source-build.sh \
  ansible/files/ipmctl/source-profile.py \
  ansible/files/ipmctl/ipmctl-inventory.py \
  ansible/files/ipmctl/compatibility-matrix.yml; do
  if [[ -e "${ROOT}/${removed}" ]]; then
    contract.error "obsolete ipmctl implementation remains: ${removed}"
  fi
done
if find "${ROOT}/actions/fixtures/ipmctl" -type f -print -quit 2>/dev/null | grep -q .; then
  contract.error "obsolete ipmctl parser fixtures remain"
fi

require_shell_syntax "setup/cli/ipmctl.sh"
require_shell_syntax "actions/test.ipmctl-contract.sh"

for marker in \
  'Usage: ipmctl.sh [install|verify]' \
  'readonly EXIT_SOFTWARE=1' \
  'readonly EXIT_HARDWARE=2' \
  'readonly EXIT_BLOCKED=3' \
  'readonly EXIT_USAGE=64' \
  'readonly IPMCTL_BIN=/usr/local/bin/ipmctl' \
  'readonly IPMCTL_VERSION=03.00.00.0538' \
  'FEATURE_PLAYBOOKS=("install.packages.yml" "cli/ipmctl.yml")' \
  'files/ipmctl/apply-patch.yml' \
  'files/ipmctl/patches/0001-edk2-stable202511-host-os-build.patch' \
  'files/ipmctl/patches/0002-ipmctl-disable-c-release-werror.patch' \
  'files/ipmctl/patches/0003-ipmctl-remove-pie-from-shared-linker-flags.patch' \
  'runner.ensure.privileged.session' \
  'runner.run.as.root "${IPMCTL_BIN}"' \
  'hardware.probe dimms "PMem DIMMs" show -a -dimm' \
  'hardware.probe topology "PMem topology" show -topology' \
  'hardware.probe memoryresources "PMem memory resources" show -memoryresources' \
  'hardware.probe goal "PMem current or pending goal" show -a -goal'; do
  require_contains "setup/cli/ipmctl.sh" "${marker}"
done

for marker in \
  'ipmctl_tag: v03.00.00.0538' \
  'ipmctl_commit: a71f2fb1c90dd07f9862b71c789881132193e8f9' \
  'ipmctl_expected_version: 03.00.00.0538' \
  'ipmctl_edk2_tag: edk2-stable202511' \
  'ipmctl_edk2_commit: 46548b1adac82211d8d11da12dd914f41e7aa775' \
  'ipmctl_install_prefix: /usr/local' \
  'ipmctl_receipt_path: /var/lib/devs-guide/ipmctl/receipt.json' \
  'Refuse an unmanaged local ipmctl binary' \
  'Determine whether installation is current' \
  'Fetch only reviewed source tags' \
  'Check out reviewed commits detached' \
  'Require exact source identities' \
  'Preserve EDK2 CRLF source as a binary Git diff' \
  'Apply finite reviewed compatibility pack' \
  'Link reviewed EDK2 components explicitly' \
  '-DRELEASE=ON' \
  '-DCMAKE_BUILD_TYPE=Release' \
  '"-DBUILDNUM={{ ipmctl_expected_version }}"' \
  'Compile reviewed Release build' \
  'Write atomic installation receipt'; do
  require_contains "ansible/cli/ipmctl.yml" "${marker}"
done

for marker in \
  'checksum_algorithm: sha256' \
  'git' \
  'apply' \
  '--numstat' \
  '--check' \
  '--whitespace=error-all' \
  '--reverse' \
  'diff' \
  'ipmctl_patch_preimage' \
  'ipmctl_patch_postimage'; do
  require_contains "ansible/files/ipmctl/apply-patch.yml" "${marker}"
done

declare -a patch_specs=(
  '0001-edk2-stable202511-host-os-build.patch|ac6f0ea143c357c582135472defe8e936a63d7997221a29d4d0e4c349d7ac013|MdePkg/Include/Base.h'
  '0002-ipmctl-disable-c-release-werror.patch|d1928dc874219578abbc9eab5cc7a826ccf88457bd148f268aff367d134321b8|CMakeLists.txt'
  '0003-ipmctl-remove-pie-from-shared-linker-flags.patch|f926a6b07ad33b09f09032e6fd06a9229855d9d0501cfc7e67ecbb4c3c28a031|CMakeLists.txt'
)

for spec in "${patch_specs[@]}"; do
  IFS='|' read -r filename expected_sha expected_target <<<"${spec}"
  patch_path="${ROOT}/ansible/files/ipmctl/patches/${filename}"
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha="$(sha256sum "${patch_path}" | awk '{print $1}')"
  else
    actual_sha="$(shasum -a 256 "${patch_path}" | awk '{print $1}')"
  fi
  [[ "${actual_sha}" == "${expected_sha}" ]] || \
    contract.error "patch checksum drifted: ${filename}: ${actual_sha}"
  actual_targets="$(git apply --numstat "${patch_path}" | awk -F '\t' 'NF >= 3 {print $3}')"
  [[ "${actual_targets}" == "${expected_target}" ]] || \
    contract.error "patch target drifted: ${filename}: ${actual_targets}"
  require_contains "ansible/cli/ipmctl.yml" "sha256: ${expected_sha}"
done

for file in setup/cli/ipmctl.sh ansible/cli/ipmctl.yml; do
  for prohibited in \
    'delete -pcd' \
    'delete -goal' \
    'delete -dimm' \
    'start -format' \
    'load -firmware' \
    'set -dimm' \
    'ndctl destroy-namespace' \
    'systemctl reboot' \
    '/sbin/reboot' \
    './updateedk.sh' \
    './patch_OS.sh' \
    '--ignore-space-change' \
    '--ignore-whitespace' \
    '--whitespace=nowarn' \
    '-Wno-error'; do
    reject_contains "${file}" "${prohibited}"
  done
done

for obsolete_interface in \
  'goal-plan' \
  'goal-apply' \
  '--allow-destructive-goal-change' \
  '--repository-url=' \
  '--commit=' \
  '--build-type='; do
  reject_contains "setup/cli/ipmctl.sh" "${obsolete_interface}"
done

help_output="$(bash "${ROOT}/setup/cli/ipmctl.sh" --help)" || \
  contract.error "ipmctl --help failed"
[[ "${help_output}" == *'Usage: ipmctl.sh [install|verify]'* ]] || \
  contract.error "ipmctl --help omitted the two-mode interface"
set +e
bash "${ROOT}/setup/cli/ipmctl.sh" unsupported-mode >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -eq 64 ]] || \
  contract.error "invalid ipmctl mode must exit 64, got ${invalid_status}"

require_contains "ansible/packages.yml" 'ipmctl_build:'
require_contains "ansible/install.packages.yml" '      - ipmctl_build'
require_contains "ansible/cli/llm/host.yml" 'llm_host_ipmctl_binary_path: /usr/local/bin/ipmctl'
require_contains "ansible/cli/llm/host.yml" 'llm_host_ipmctl_expected_version: 03.00.00.0538'
reject_contains "ansible/cli/llm/host.yml" '/etc/ansible/debian/facts/ipmctl.yml'
require_contains ".github/workflows/www.pages.yml" 'validate-runtime:'
reject_contains ".github/workflows/www.pages.yml" 'validate-ipmctl-source'
require_contains "actions/publication.manifest" 'file|setup/cli/ipmctl.sh|setup/cli/ipmctl.sh'
require_contains "actions/publication.manifest" 'tree|ansible|ansible'

if ! validate_yaml_file "${ROOT}/ansible/cli/ipmctl.yml"; then
  rc=1
fi
if ! validate_yaml_file "${ROOT}/ansible/files/ipmctl/apply-patch.yml"; then
  rc=1
fi
if ! validate_shell_payloads "${ROOT}/ansible/cli/ipmctl.yml"; then
  rc=1
fi

if [[ "${SHELL_ONLY}" -eq 0 ]] && command -v ansible-playbook >/dev/null 2>&1; then
  if ! ansible-playbook --syntax-check -i localhost, \
    -e ansible_python_interpreter_managed=/usr/bin/python3 \
    -e ipmctl_build_user=nobody \
    -e ipmctl_build_group=nogroup \
    -e ipmctl_build_home=/tmp \
    "${ROOT}/ansible/cli/ipmctl.yml"; then
    contract.error "ipmctl playbook failed ansible-playbook --syntax-check"
  fi
elif [[ "${SHELL_ONLY}" -eq 0 ]]; then
  contract.warn "ansible-playbook unavailable; syntax check deferred to CI"
else
  echo "[${ACTION_LABEL}] shell-only mode: deferred Ansible syntax check to CI"
fi

exit "${rc}"
