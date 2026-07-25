#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="${ROOT}/actions/fixtures/nvidia.register-normalization.yml"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-}"

log() {
  printf '[test.nvidia-facts] %s\n' "$*" >&2
}

fail() {
  printf '[test.nvidia-facts][error] %s\n' "$*" >&2
  exit 1
}

if [[ -z "${ANSIBLE_PLAYBOOK}" ]]; then
  ANSIBLE_PLAYBOOK="$(command -v ansible-playbook || true)"
fi

[[ -n "${ANSIBLE_PLAYBOOK}" && -x "${ANSIBLE_PLAYBOOK}" ]] || \
  fail "ansible-playbook is unavailable; install the pinned CI validation dependencies first."
[[ -r "${FIXTURE}" ]] || fail "Regression fixture is missing: ${FIXTURE}"
[[ -r "${ROOT}/ansible/tasks/nvidia.normalize-observations.yml" ]] || \
  fail "Shared NVIDIA normalization task is missing."

python3 -c 'import yaml' >/dev/null 2>&1 || \
  fail "PyYAML is unavailable; install the pinned CI validation dependencies first."

log "running skipped-register normalization regression"
ANSIBLE_NOCOLOR=1 \
  "${ANSIBLE_PLAYBOOK}" \
    -i localhost, \
    -c local \
    "${FIXTURE}"
