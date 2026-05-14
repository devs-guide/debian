#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

files=(
  "setup/bootstrap.sh"
  "setup/debian.sh"
  "setup/metal.sh"
  "setup/release.common.sh"
  "setup/cli.codex.sh"
  "actions/www.pages.sh"
  "actions/validate.runtime.sh"
  "actions/validate.pages.sh"
  "ansible/install.playbooks.txt"
  "ansible/bootstrap.yml"
  "ansible/install.packages.yml"
  "ansible/packages.yml"
  "ansible/network.yml"
  "ansible/users.yml"
  "ansible/lan.yml"
  "ansible/ssh.yml"
  "ansible/sources.yml"
  "ansible/node.yml"
  "ansible/cli/codex.yml"
  "ansible/group_vars/all.yml"
  "ansible/group_vars/debian.yml"
  "ansible/group_vars/trixie.yml"
  "www/index.html"
  "readme.md"
)

echo "[validate.runtime] checking required files..."
for f in "${files[@]}"; do
  if [[ -f "${ROOT}/${f}" ]]; then
    echo "[ok] ${f}"
  else
    echo "[missing] ${f}"
    rc=1
  fi
done

echo "[validate.runtime] checking playlist references..."
while IFS= read -r ref; do
  [[ -n "${ref}" ]] || continue
  [[ "${ref}" =~ ^[[:space:]]*# ]] && continue
  if [[ ! -f "${ROOT}/ansible/${ref}" ]]; then
    echo "[validate.runtime][error] missing playlist entry: ansible/${ref}"
    rc=1
  fi
done < <(sed 's/[[:space:]]*$//' "${ROOT}/ansible/install.playbooks.txt" | grep -vE '^[[:space:]]*(#|$)')

echo "[validate.runtime] checking bootstrap playlist scope..."
if grep -qx 'node.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] minimal bootstrap playlist must not include node.yml"
  rc=1
fi
if grep -qx 'ansible.venv.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] minimal bootstrap playlist must not include ansible.venv.yml"
  rc=1
fi
if ! grep -qx 'users.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include users.yml"
  rc=1
fi
if ! grep -qx 'network.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include network.yml"
  rc=1
fi
if grep -q 'allow_rdp:[[:space:]]*true' "${ROOT}/ansible/lan.yml"; then
  echo "[validate.runtime][error] minimal bootstrap must not enable RDP by default"
  rc=1
fi

echo "[validate.runtime] checking setup.cli.codex.sh runner contract..."
if ! grep -q '"node.yml"' "${ROOT}/setup/cli.codex.sh"; then
  echo "[validate.runtime][error] setup/cli.codex.sh must reference node.yml"
  rc=1
fi
if ! grep -q '"cli/codex.yml"' "${ROOT}/setup/cli.codex.sh"; then
  echo "[validate.runtime][error] setup/cli.codex.sh must reference cli/codex.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli.codex.sh"; then
  echo "[validate.runtime][error] setup/cli.codex.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli.codex.sh"; then
  echo "[validate.runtime][error] setup/cli.codex.sh must use ensure.local.ansible"
  rc=1
fi

echo "[validate.runtime] checking for active Proxmox residue in runtime files..."
if rg -n 'proxmox|pveversion|vmbr|pct |qm |/etc/ansible/proxmox|devs-guide.github.io/proxmox' \
  "${ROOT}/setup/bootstrap.sh" \
  "${ROOT}/setup/debian.sh" \
  "${ROOT}/setup/metal.sh" \
  "${ROOT}/setup/release.common.sh" \
  "${ROOT}/setup/cli.codex.sh" \
  "${ROOT}/actions/www.pages.sh" \
  "${ROOT}/actions/validate.pages.sh" \
  "${ROOT}/ansible" \
  "${ROOT}/ansible/group_vars" \
  "${ROOT}/www/index.html" \
  "${ROOT}/readme.md" >/dev/null; then
  echo "[validate.runtime][error] active runtime files still contain Proxmox-only markers"
  rc=1
fi

exit "${rc}"
