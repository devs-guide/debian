#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

files=(
  "setup/bootstrap.sh"
  "setup/debian.sh"
  "setup/metal.sh"
  "setup/hardware.sh"
  "setup/cli/node.sh"
  "setup/release.common.sh"
  "setup/cli/codex.sh"
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
  "ansible/cli/node.yml"
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
if ! grep -qx 'security.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include security.yml"
  rc=1
fi
if ! grep -qx 'sysctl.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include sysctl.yml"
  rc=1
fi
if ! grep -qx 'network.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include network.yml"
  rc=1
fi
if ! grep -qx 'logging.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] bootstrap playlist must include logging.yml"
  rc=1
fi
if grep -qx 'ssh.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] ssh.yml is a runtime vars/support file and must not be listed as a playlist playbook"
  rc=1
fi
if grep -q 'allow_rdp:[[:space:]]*true' "${ROOT}/ansible/lan.yml"; then
  echo "[validate.runtime][error] minimal bootstrap must not enable RDP by default"
  rc=1
fi
if sed -n '/^[[:space:]]*handlers:/,$p' "${ROOT}/ansible/network.yml" | grep -q '^[[:space:]]*block:'; then
  echo "[validate.runtime][error] ansible/network.yml handlers must not use block; use concrete handlers with listen topics"
  rc=1
fi
if ! grep -q 'listen: Validate and reload ssh' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] ansible/network.yml must use listen handlers for SSH validate/reload"
  rc=1
fi
if ! grep -q 'Resolve SSH service unit name' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] ansible/network.yml must resolve the Debian SSH service unit before notifying reload handlers"
  rc=1
fi
if ! grep -q 'bootstrap_default_user_update_password: "always"' "${ROOT}/ansible/group_vars/all.yml"; then
  echo "[validate.runtime][error] default bootstrap users must refresh passwords on repeat bootstrap runs"
  rc=1
fi
if ! grep -A12 'name: app' "${ROOT}/ansible/group_vars/all.yml" | grep -q 'sudo'; then
  echo "[validate.runtime][error] default app user must have sudo group membership"
  rc=1
fi
if ! grep -q 'update_password: "{{ item.update_password | default(bootstrap_default_user_update_password' "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml must use bootstrap_default_user_update_password, not hard-coded on_create"
  rc=1
fi
if grep -q 'update_password: on_create' "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml must not hard-code update_password: on_create for bootstrap accounts"
  rc=1
fi
if ! grep -q "item.groups is defined" "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml must compute append/groups from explicit user group inputs"
  rc=1
fi
if ! grep -q "rejectattr('name', 'equalto', 'root')" "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml must verify sudo only for non-root managed users"
  rc=1
fi
if ! grep -q "rejectattr('skipped', 'defined')" "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml sudo assertion must reject skipped registered loop results"
  rc=1
fi
if grep -q "item.stdout.split()" "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml must not dereference item.stdout without a default/defined guard"
  rc=1
fi
if ! grep -q "item.stdout is defined" "${ROOT}/ansible/users.yml"; then
  echo "[validate.runtime][error] users.yml sudo assertion must guard item.stdout"
  rc=1
fi
if ! grep -q 'Ensure sshd_config loads managed drop-ins' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must enforce sshd_config Include for managed drop-ins"
  rc=1
fi
if ! grep -q 'Apply SSH policy before firewall changes' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must flush SSH handlers before enabling UFW"
  rc=1
fi
if ! grep -q 'Allow all TCP from permitted LAN subnets for bootstrap access' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must add broad LAN TCP bootstrap UFW allow rule"
  rc=1
fi
if ! grep -q 'ufw allow from {{ item }} to any proto tcp' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must create exact UFW LAN TCP allow rule"
  rc=1
fi
if ! grep -q 'Assert SSH password and root bootstrap access is active' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must validate effective SSH bootstrap access"
  rc=1
fi
if ! grep -q 'Assert permitted LAN subnet appears in UFW rules' "${ROOT}/ansible/network.yml"; then
  echo "[validate.runtime][error] network.yml must validate UFW LAN subnet rules"
  rc=1
fi

echo "[validate.runtime] checking bootstrap resolver contract..."
if ! grep -q 'resolve.release.groupvars.file' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must resolve Debian release lanes explicitly"
  rc=1
fi
if ! grep -q 'resolve.controller.python.policy' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must resolve controller Python policy before Ansible setup"
  rc=1
fi
if ! grep -q 'Bootstrap entry sha256' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must log a bootstrap entry revision marker"
  rc=1
fi
if ! grep -q 'select.python.bootstrap.bin' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must route controller Python selection through policy-aware provider logic"
  rc=1
fi
if ! grep -q 'RUNTIME_SUPPORT_REFS=(packages.yml ssh.yml)' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must fetch runtime support refs including packages.yml and ssh.yml"
  rc=1
fi
if ! grep -q 'fetch.runtime.support.files' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must fetch runtime support files before playlist execution"
  rc=1
fi
if ! grep -q 'debian.native.python.version.hint' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must contain Debian native Python policy map"
  rc=1
fi
if ! grep -q 'CONTROLLER_PYTHON_PROVIDER' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must use release-aware controller Python provider"
  rc=1
fi
if ! grep -q 'select.system.controller.python' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must support distro Python controller selection"
  rc=1
fi
if ! grep -q 'ensure.managed.fallback.python.build' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must support managed fallback Python builds for legacy releases"
  rc=1
fi
if ! grep -q 'python.version.matches.controller.minimum' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must enforce controller minimum Python version checks"
  rc=1
fi
if ! grep -q 'python.can.create.venv' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must probe venv capability before creating /opt/ansible-venv"
  rc=1
fi
if ! grep -q 'Existing managed fallback Python violates fallback contract' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must reject stale /opt/ansible/py312 that violates fallback contract"
  rc=1
fi
if ! grep -q 'ansible.venv.python.matches.controller.minimum' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must validate existing /opt/ansible-venv Python version"
  rc=1
fi
if ! grep -q 'ansible.venv.core.version' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must parse ansible-playbook core version from bracketed output"
  rc=1
fi
if ! grep -q 'controller_python_provider' "${ROOT}/ansible/group_vars/trixie.yml"; then
  echo "[validate.runtime][error] trixie.yml must declare controller_python_provider"
  rc=1
fi
if ! grep -q 'controller_python_provider' "${ROOT}/ansible/group_vars/buster.yml"; then
  echo "[validate.runtime][error] buster.yml must declare controller_python_provider"
  rc=1
fi
if ! grep -q 'controller_python_provider: "system"' "${ROOT}/ansible/group_vars/trixie.yml"; then
  echo "[validate.runtime][error] trixie.yml must select system controller Python"
  rc=1
fi
if ! grep -q 'controller_python_provider: "managed_source"' "${ROOT}/ansible/group_vars/buster.yml"; then
  echo "[validate.runtime][error] buster.yml must select managed_source controller Python"
  rc=1
fi
if ! grep -q 'PYTHON_MIN_VERSION' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must define PYTHON_MIN_VERSION"
  rc=1
fi
if ! grep -q 'Bootstrap selection marker' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must record bootstrap selection details"
  rc=1
fi
if ! grep -q 'Bootstrap helper sha256' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must log a helper revision marker"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'REFRESH' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must support REFRESH"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must use neutral /tmp/ansible/debian runtime paths"
  rc=1
fi
if ! grep -q 'runtime_helper_sha256=' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must persist helper revision details in the selection marker"
  rc=1
fi
if ! sed -n '/ensure.managed.ansible()/,/^}/p' "${ROOT}/setup/release.common.sh" | grep -q 'ansible.venv.python.matches.controller.minimum'; then
  echo "[validate.runtime][error] ensure.managed.ansible() must verify existing Ansible venv Python contract before reuse"
  rc=1
fi
if ! sed -n '/ensure.managed.ansible()/,/^}/p' "${ROOT}/setup/release.common.sh" | grep -q 'ansible.venv.core.matches.contract'; then
  echo "[validate.runtime][error] ensure.managed.ansible() must use non-brittle ansible core contract checks compatible with bracketed output"
  rc=1
fi
if ! sed -n '/ensure.managed.ansible()/,/^}/p' "${ROOT}/setup/release.common.sh" | grep -q 'python.can.create.venv'; then
  echo "[validate.runtime][error] ensure.managed.ansible() must validate managed Python can create Ansible venvs"
  rc=1
fi
if ! sed -n '/run.playlist()/,/^}/p' "${ROOT}/setup/release.common.sh" | grep -q 'playbook_paths'; then
  echo "[validate.runtime][error] run.playlist() must execute playlist entries in a single ansible invocation"
  rc=1
fi
if ! grep -q 'ansible_python_interpreter_managed: "/usr/bin/python3"' "${ROOT}/ansible/group_vars/trixie.yml"; then
  echo "[validate.runtime][error] trixie.yml must force managed/module interpreter to /usr/bin/python3"
  rc=1
fi
if ! grep -q 'ansible_python_interpreter_managed: "/opt/ansible/py312/bin/python"' "${ROOT}/ansible/group_vars/buster.yml"; then
  echo "[validate.runtime][error] buster.yml must force managed/module interpreter to /opt/ansible/py312/bin/python"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/node.sh runner contract..."
if ! grep -q '"cli/node.yml"' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must reference cli/node.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_NODE_MODE' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support DEBIAN_NODE_MODE"
  rc=1
fi
if ! grep -Fq 'DEBIAN_NODE_VERSION:-lts/*' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must default DEBIAN_NODE_VERSION to lts/*"
  rc=1
fi
if ! grep -Fq 'DEBIAN_NODE_NPM_POLICY:-bundled' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must default npm policy to bundled"
  rc=1
fi
if ! grep -q 'preflight|apply|upgrade' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support preflight, apply, and upgrade modes"
  rc=1
fi
if rg -n 'codex|tauri' "${ROOT}/setup/cli/node.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/cli/node.sh must not install codex or tauri directly"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/node.yml contract..."
if [[ -e "${ROOT}/ansible/node.yml" ]]; then
  echo "[validate.runtime][error] ansible/node.yml must not exist; cli/node.yml is the canonical node feature path"
  rc=1
fi
if ! grep -q 'node_version: "lts/\*"' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must default node_version to lts/*"
  rc=1
fi
if ! grep -q 'node_npm_policy: "bundled"' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must default npm policy to bundled"
  rc=1
fi
if ! grep -q '/usr/local/bin/node' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must manage /usr/local/bin/node symlink"
  rc=1
fi
if ! grep -q '/usr/local/bin/npm' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must manage /usr/local/bin/npm symlink"
  rc=1
fi
if ! grep -q '/usr/local/bin/npx' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must manage /usr/local/bin/npx symlink"
  rc=1
fi
if ! grep -q 'node_runtime_facts_path' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must write node runtime facts"
  rc=1
fi
if sed -n '/Write node runtime facts/,/^      when:/p' "${ROOT}/ansible/cli/node.yml" | grep -q 'regex_search'; then
  echo "[validate.runtime][error] ansible/cli/node.yml must not use regex_search directly inside the node facts writer"
  rc=1
fi
if ! grep -q 'Validate final Node runtime details' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must validate captured Node/npm/npx details before writing facts"
  rc=1
fi
if ! grep -q 'Normalize final Node runtime facts' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must normalize runtime facts before writing node facts"
  rc=1
fi
if ! grep -q 'regex_findall' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must use list-safe regex_findall/default parsing for runtime facts"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/codex.sh runner contract..."
if ! grep -q '"cli/node.yml"' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must reference cli/node.yml"
  rc=1
fi
if ! grep -q '"cli/codex.yml"' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must reference cli/codex.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi

echo "[validate.runtime] checking setup/hardware.sh runner contract..."
if ! grep -q '"install.packages.yml"' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must reference install.packages.yml"
  rc=1
fi
if ! grep -q '"performance.yml"' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must reference performance.yml"
  rc=1
fi
if ! grep -q '"power.yml"' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must reference power.yml"
  rc=1
fi
if ! grep -q 'RUNTIME_SUPPORT_REFS=(' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must define RUNTIME_SUPPORT_REFS"
  rc=1
fi
if ! grep -q '"packages.yml"' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must fetch packages.yml support catalog"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'storage: true' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must enable storage group by default"
  rc=1
fi
if ! grep -q 'hardware_info: true' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must enable hardware_info group by default"
  rc=1
fi
if ! grep -q 'monitoring_benchmark: true' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must enable monitoring_benchmark group by default"
  rc=1
fi
if ! grep -q 'performance_power: true' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must enable performance_power group by default"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_FIRMWARE=.*:-0' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must default DEBIAN_HARDWARE_FIRMWARE to off"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_DEV_TOOLS=.*:-0' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must default DEBIAN_HARDWARE_DEV_TOOLS to off"
  rc=1
fi
if ! grep -q 'desktop_rdp_optional: false' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must keep desktop_rdp_optional disabled by default"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_APPLY_PERFORMANCE=.*:-0' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must default DEBIAN_HARDWARE_APPLY_PERFORMANCE to off"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_POWER_POLICY=.*:-0' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must default DEBIAN_HARDWARE_POWER_POLICY to off"
  rc=1
fi
if ! grep -q 'preflight|apply' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must support preflight and apply modes"
  rc=1
fi
if ! grep -q 'package_group_allowlist' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must pass package_group_allowlist"
  rc=1
fi
if grep -q 'gpu_vendor_optional:[[:space:]]*true' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must not enable gpu_vendor_optional"
  rc=1
fi
if ! grep -q 'exclude_packages:' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must define exclude_packages safety guards"
  rc=1
fi
if awk '
  $0 ~ /^  monitoring_benchmark:/ { in_block=1; next }
  in_block && $0 ~ /^  [a-z0-9_]+:/ { in_block=0 }
  in_block { print }
' "${ROOT}/ansible/packages.yml" | grep -q 'radeontop'; then
  echo "[validate.runtime][error] radeontop must not be in monitoring_benchmark; reserve it for setup/gpu"
  rc=1
fi
if ! sed -n '/gpu_vendor_optional:/,/^[^[:space:]]/p' "${ROOT}/ansible/packages.yml" | grep -q 'radeontop'; then
  echo "[validate.runtime][error] gpu_vendor_optional must own radeontop"
  rc=1
fi
if ! grep -q 'package_group_allowlist_effective' "${ROOT}/ansible/install.packages.yml"; then
  echo "[validate.runtime][error] install.packages.yml must support feature-scoped package_group_allowlist"
  rc=1
fi
if ! grep -q 'effective_catalog_scoped' "${ROOT}/ansible/install.packages.yml"; then
  echo "[validate.runtime][error] install.packages.yml must scope effective catalog for feature runners"
  rc=1
fi
if ! grep -q 'enabled_package_group_items' "${ROOT}/ansible/install.packages.yml"; then
  echo "[validate.runtime][error] install.packages.yml must build an enabled package group list"
  rc=1
fi
if ! grep -q 'repair.debian.apt.sources.duplicates' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must repair duplicate apt sources before direct apt-get update"
  rc=1
fi
if ! grep -q 'apt.update.with.source.repair' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must wrap apt-get update with duplicate-source detection and retry"
  rc=1
fi
if [[ "$(grep -c 'apt-get update -y' "${ROOT}/setup/release.common.sh")" -ne 2 ]]; then
  echo "[validate.runtime][error] setup/release.common.sh must keep apt-get update calls contained in apt.update.with.source.repair"
  rc=1
fi
if ! grep -q 'disable.legacy.debian.sources.file' "${ROOT}/setup/release.common.sh"; then
  echo "[validate.runtime][error] setup/release.common.sh must disable duplicate legacy Debian .list sources, not only /etc/apt/sources.list"
  rc=1
fi
if ! grep -q 'Disable legacy apt sources list when using deb822 sources' "${ROOT}/ansible/sources.yml"; then
  echo "[validate.runtime][error] sources.yml must disable legacy /etc/apt/sources.list on deb822 releases"
  rc=1
fi
if ! grep -q 'Disable legacy apt sources list when using deb822 sources' "${ROOT}/ansible/sources.trixie.yml"; then
  echo "[validate.runtime][error] sources.trixie.yml must disable legacy /etc/apt/sources.list on deb822 releases"
  rc=1
fi

echo "[validate.runtime] checking for active Proxmox residue in runtime files..."
if rg -n 'proxmox|pveversion|vmbr|pct |qm |/etc/ansible/proxmox|devs-guide.github.io/proxmox' \
  "${ROOT}/setup/bootstrap.sh" \
  "${ROOT}/setup/debian.sh" \
  "${ROOT}/setup/metal.sh" \
  "${ROOT}/setup/hardware.sh" \
  "${ROOT}/setup/cli/node.sh" \
  "${ROOT}/setup/release.common.sh" \
  "${ROOT}/setup/cli/codex.sh" \
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
