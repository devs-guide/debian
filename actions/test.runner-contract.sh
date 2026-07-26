#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.runner-contract"
rc=0

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

echo "[${ACTION_LABEL}] checking delegated-root and staging contracts..."

runner_helper="setup/runner.common.sh"
require_shell_syntax "${runner_helper}"
for marker in \
  'runner.euid' \
  'runner.have.controlling.tty' \
  'runner.confirm.exact' \
  'runner.authenticate.sudo' \
  'runner.ensure.privileged.session' \
  'runner.run.as.root' \
  'runner.cleanup.runtime' \
  'runner.relative.path.is.safe' \
  'runner.fetch.file' \
  'runner.copy.file' \
  'runner.commit.staged.file' \
  'runner.verify.manifest' \
  'runner.require.indexed.array' \
  'runner.stage.manifest' \
  'runner.stage.ansible.feature' \
  'runner.source.release.common' \
  'runner.prepare.ansible.feature' \
  'runner.ensure.local.ansible' \
  'runner.run.ansible.playbooks' \
  'runner.report.command' \
  'runner.report.text' \
  'RUNNER_TTY_PATH:=/dev/tty' \
  'sudo -v <"${RUNNER_TTY_PATH}"' \
  'sudo -n --' \
  'mktemp -d'; do
  require_contains "${runner_helper}" "${marker}"
done

for runner in setup/cli/gpu.sh setup/cli/llm/host.sh setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  runner_path="${ROOT}/${runner}"
  direct_fetch_count="$(
    grep -Ec '^[[:space:]]*(if[[:space:]]+![[:space:]]+)?wget[[:space:]]+-qO[[:space:]]' "${runner_path}" || true
  )"
  require_shell_syntax "${runner}"
  for marker in \
    'RUNNER_HELPER_URL' \
    'source.runner.common' \
    'runner.ensure.privileged.session' \
    'runner.source.release.common' \
    'runner.prepare.ansible.feature' \
    'runner.run.ansible.playbooks' \
    'runner.report.command' \
    'FEATURE_TEMPLATE_REFS=()' \
    'mktemp -d'; do
    require_contains "${runner}" "${marker}"
  done
  for marker in \
    'fail.streamed.managed.mode' \
    'runner was executed from stdin' \
    'ensure.root.or.sudo.reexec' \
    'current.script.path' \
    'use.local.feature.files' \
    'fetch.feature.file' \
    'fetch.runtime.support.file' \
    'fetch.file()' \
    'exec sudo'; do
    reject_contains "${runner}" "${marker}"
  done
  if grep -Eq 'sudo[[:space:]]+-E([[:space:]]|$)|sudo[^#]*(wget|curl)' "${runner_path}"; then
    contract.error "${runner} must not preserve the ambient environment or fetch inside sudo"
  fi
  if [[ "${direct_fetch_count}" -ne 1 ]]; then
    contract.error "${runner} may directly fetch only the shared-runner bootstrap; found ${direct_fetch_count}"
  fi
done

for runner in setup/cli/llm/host.sh setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  require_contains "${runner}" 'runner.ensure.local.ansible'
done

reject_regex "setup/runner.common.sh" 'NVIDIA|NVLINK|nvidia_|nvlink_'
reject_regex "setup/release.common.sh" '^RUNTIME_SUPPORT_REFS='
for marker in \
  'ensure-local-ansible)' \
  'release.common.main "$@"' \
  'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then'; do
  require_contains "setup/release.common.sh" "${marker}"
done

legacy_runner_inventory="${ROOT}/docs/setup/runner-common/readme.md"
while IFS= read -r legacy_runner_path; do
  legacy_runner_rel="${legacy_runner_path#"${ROOT}/"}"
  if ! grep -Fq "\`${legacy_runner_rel}\`" "${legacy_runner_inventory}"; then
    contract.error "shared-runner migration inventory is missing ${legacy_runner_rel}"
  fi
done < <(
  find "${ROOT}/setup" -type f -name '*.sh' \
    -exec grep -l 'ensure\.root\.or\.sudo\.reexec' {} + \
    | sort
)
for migrated_runner in setup/cli/gpu.sh setup/cli/llm/host.sh setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  if sed -n '/The following legacy runners/,/They remain unchanged/p' "${legacy_runner_inventory}" \
    | grep -Fq "\`${migrated_runner}\`"; then
    contract.error "migration inventory incorrectly marks ${migrated_runner} as legacy"
  fi
done

require_shell_syntax "actions/test.runner-staging.sh"
require_shell_syntax "actions/test.sudo-access.sh"
run_contract_action "actions/test.runner-staging.sh"
run_contract_action "actions/test.sudo-access.sh"

exit "${rc}"
