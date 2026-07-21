#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

search_regex() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -n -- "${pattern}" "$@"
    return
  fi

  grep -R -nE -- "${pattern}" "$@"
}

validate_yaml_file() {
  local f="$1"

  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "$f" <<'PY'
from pathlib import Path
import sys
import yaml

path = Path(sys.argv[1])
try:
    yaml.safe_load(path.read_text())
except Exception as exc:
    print(f"[validate.runtime][error] invalid YAML: {path}: {exc}")
    raise SystemExit(1)
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby - "$f" <<'RUBY'
require "yaml"

path = ARGV.fetch(0)
begin
  YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
rescue => e
  warn "[validate.runtime][error] invalid YAML: #{path}: #{e}"
  exit 1
end
RUBY
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    echo "[validate.runtime][warn] YAML parser unavailable; running heredoc indentation regression check: ${f}"
    python3 - "$f" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()

i = 0
while i < len(lines):
    line = lines[i]
    if "python3 -" not in line or "<<" not in line or "PY" not in line:
        i += 1
        continue

    base_indent = len(line) - len(line.lstrip(" "))
    j = i + 1
    found_terminator = False

    while j < len(lines):
        candidate = lines[j]
        candidate_indent = len(candidate) - len(candidate.lstrip(" "))
        stripped = candidate.strip()

        if stripped == "PY":
            if candidate_indent < base_indent:
                print(
                    f"[validate.runtime][error] malformed heredoc terminator indentation in {path}: line {j + 1}"
                )
                raise SystemExit(1)
            found_terminator = True
            break

        if stripped and candidate_indent < base_indent:
            print(
                f"[validate.runtime][error] malformed heredoc body indentation in {path}: line {j + 1}"
            )
            raise SystemExit(1)
        j += 1

    if not found_terminator:
        print(f"[validate.runtime][error] unterminated heredoc block in {path}: line {i + 1}")
        raise SystemExit(1)

    i = j + 1
PY
    return
  fi

  echo "[validate.runtime][error] no YAML parser available for ${f} (python3+pyyaml, ruby, or python3 fallback required)"
  return 1
}

validate_shell_payloads() {
  local f="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[validate.runtime][error] python3 is required to validate shell payloads in ${f}"
    return 1
  fi

  python3 - "$f" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

path = Path(sys.argv[1])
text = path.read_text()

def neutralize_jinja(payload: str) -> str:
    payload = re.sub(r"\{\{.*?\}\}", "0", payload, flags=re.S)
    payload = re.sub(r"\{%.*?%\}", "", payload, flags=re.S)
    payload = re.sub(r"\{#.*?#\}", "", payload, flags=re.S)
    return payload

def extract_with_yaml(raw: str):
    try:
        import yaml
    except Exception:
        return None, None
    try:
        docs = yaml.safe_load(raw)
    except Exception as exc:
        return None, f"[validate.runtime][error] invalid YAML while extracting shell payloads: {path}: {exc}"

    blocks = []
    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("shell", "ansible.builtin.shell") and isinstance(value, str):
                    blocks.append(value)
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)
    walk(docs)
    return blocks, None

def extract_with_text_scan(raw: str):
    lines = raw.splitlines()
    blocks = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^(\s*)(?:ansible\.builtin\.shell|shell):\s*\|\s*$", line)
        if not m:
            i += 1
            continue
        base_indent = len(m.group(1))
        j = i + 1
        payload_lines = []
        while j < len(lines):
            current = lines[j]
            if current.strip() == "":
                payload_lines.append("")
                j += 1
                continue
            current_indent = len(current) - len(current.lstrip(" "))
            if current_indent <= base_indent:
                break
            # YAML block content is conventionally indented by at least 2 spaces.
            trim = min(len(current), base_indent + 2)
            payload_lines.append(current[trim:])
            j += 1
        blocks.append("\n".join(payload_lines) + "\n")
        i = j
    return blocks

shell_blocks, parse_error = extract_with_yaml(text)
if parse_error:
    print(parse_error)
    raise SystemExit(1)
if shell_blocks is None:
    shell_blocks = extract_with_text_scan(text)

for idx, raw_payload in enumerate(shell_blocks, start=1):
    payload = neutralize_jinja(raw_payload)
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as tmp:
        tmp.write(payload)
        tmp_path = tmp.name
    try:
        result = subprocess.run(
            ["bash", "-n", tmp_path],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            print(f"[validate.runtime][error] shell payload parse failed: {path} block#{idx}")
            if stderr:
                print(stderr)
            raise SystemExit(1)
    finally:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass
PY
}

require_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq -- "${pattern}" "${ROOT}/${file}"; then
    echo "[validate.runtime][error] missing pattern in ${file}: ${pattern}"
    rc=1
  fi
}

reject_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "${pattern}" "${ROOT}/${file}"; then
    echo "[validate.runtime][error] unexpected pattern in ${file}: ${pattern}"
    rc=1
  fi
}

files=(
  "setup/bootstrap.sh"
  "setup/debian.sh"
  "setup/metal.sh"
  "setup/hardware.sh"
  "setup/autologin.sh"
  "setup/cli/node.sh"
  "setup/cli/x11.sh"
  "setup/cli/openbox.sh"
  "setup/cli/touchscreen.sh"
  "setup/release.common.sh"
  "setup/cli/codex.sh"
  "setup/cli/kiosk.app.sh"
  "setup/cli/startx.sh"
  "setup/cli/tauri.sh"
  "setup/cli/nvidia.sh"
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
  "ansible/cli/x11.yml"
  "ansible/cli/openbox.yml"
  "ansible/cli/touchscreen.yml"
  "ansible/cli/tauri.yml"
  "ansible/cli/nvidia.yml"
  "ansible/cli/startx.yml"
  "ansible/autologin.yml"
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
if ! grep -q 'ensure.root.or.sudo.reexec' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must support sudo re-entry"
  rc=1
fi
if ! grep -q 'DEBIAN_BOOTSTRAP_SUDO_REEXEC' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must support DEBIAN_BOOTSTRAP_SUDO_REEXEC"
  rc=1
fi
if ! grep -q 'DEBIAN_BOOTSTRAP_SELF_URL' "${ROOT}/setup/bootstrap.sh"; then
  echo "[validate.runtime][error] setup/bootstrap.sh must support DEBIAN_BOOTSTRAP_SELF_URL"
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
if ! grep -q 'DEBIAN_NODE_INSTALL_SCOPE' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support DEBIAN_NODE_INSTALL_SCOPE"
  rc=1
fi
if ! grep -q 'DEBIAN_NODE_SHARED_NVM_DIR' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support DEBIAN_NODE_SHARED_NVM_DIR"
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
if ! grep -q 'ensure.root.or.sudo.reexec' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support sudo re-entry"
  rc=1
fi
if ! grep -q 'DEBIAN_NODE_SUDO_REEXEC' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support DEBIAN_NODE_SUDO_REEXEC"
  rc=1
fi
if ! grep -q 'DEBIAN_NODE_SELF_URL' "${ROOT}/setup/cli/node.sh"; then
  echo "[validate.runtime][error] setup/cli/node.sh must support DEBIAN_NODE_SELF_URL"
  rc=1
fi
node_ensure_line="$(grep -n 'ensure.root.or.sudo.reexec "\$@"' "${ROOT}/setup/cli/node.sh" | tail -n1 | cut -d: -f1)"
node_source_line="$(grep -n 'source.release.common' "${ROOT}/setup/cli/node.sh" | tail -n1 | cut -d: -f1)"
if [[ -z "${node_ensure_line}" || -z "${node_source_line}" || "${node_ensure_line}" -ge "${node_source_line}" ]]; then
  echo "[validate.runtime][error] setup/cli/node.sh must re-enter with sudo before sourcing release.common"
  rc=1
fi
if search_regex 'codex|tauri' "${ROOT}/setup/cli/node.sh" >/dev/null; then
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
if ! grep -q 'node_min_major' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must define node_min_major"
  rc=1
fi
if ! grep -q 'node_install_policy' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must define node_install_policy"
  rc=1
fi
if ! grep -q 'node_install_scope' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must define node_install_scope"
  rc=1
fi
if ! grep -q 'node_shared_nvm_dir' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must define node_shared_nvm_dir"
  rc=1
fi
if ! grep -q 'node_install_needed' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must compute node_install_needed"
  rc=1
fi
if ! grep -q 'node_nvm_dir_effective' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must derive node_nvm_dir_effective"
  rc=1
fi
if ! grep -q 'node_scope_ok' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must emit node_scope_ok probe data"
  rc=1
fi
if ! grep -q 'node_runtime_ok' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must emit node_runtime_ok probe data"
  rc=1
fi
if ! grep -q 'node_npm_min_major' "${ROOT}/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] ansible/cli/node.yml must define node_npm_min_major"
  rc=1
fi
if ! grep -q 'node_npm_min_major' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define node_npm_min_major"
  rc=1
fi
if ! grep -q 'node_install_scope' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define node_install_scope"
  rc=1
fi
if ! grep -q 'node_shared_nvm_dir' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define node_shared_nvm_dir"
  rc=1
fi
if ! grep -q 'autologin_mode' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define autologin_mode defaults"
  rc=1
fi
if ! grep -q 'autologin_user' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define autologin_user defaults"
  rc=1
fi
if ! grep -q 'autologin_tty' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define autologin_tty defaults"
  rc=1
fi
if ! grep -q 'tauri_rust_create_system_symlinks' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define tauri_rust_create_system_symlinks"
  rc=1
fi
if ! grep -q 'tauri_node_install_scope' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define tauri_node_install_scope"
  rc=1
fi
if ! grep -q 'tauri_node_shared_nvm_dir' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define tauri_node_shared_nvm_dir"
  rc=1
fi
if ! grep -q 'tauri_rust_profile_hook_path' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define tauri_rust_profile_hook_path"
  rc=1
fi
if ! grep -q 'tauri_rust_shell_validate' "${ROOT}/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] ansible/group_vars/debian.yml must define tauri_rust_shell_validate"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/codex.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must pass bash -n"
  rc=1
fi
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
if ! grep -q 'DEBIAN_CLI_CODEX_MODE' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_CODEX_NODE_SHARED_NVM_DIR' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_NODE_SHARED_NVM_DIR"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_CODEX_NODE_NVM_DIR' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_NODE_NVM_DIR"
  rc=1
fi
if ! grep -Fq 'DEBIAN_CLI_CODEX_NODE_VERSION:-lts/*' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must default DEBIAN_CLI_CODEX_NODE_VERSION to lts/*"
  rc=1
fi
if ! grep -Fq 'DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE:-shared' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must default Node install scope to shared"
  rc=1
fi
if ! grep -q 'ensure.root.or.sudo.reexec' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support sudo re-entry"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_CODEX_SUDO_REEXEC' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_SUDO_REEXEC"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_CODEX_SELF_URL' "${ROOT}/setup/cli/codex.sh"; then
  echo "[validate.runtime][error] setup/cli/codex.sh must support DEBIAN_CLI_CODEX_SELF_URL"
  rc=1
fi
codex_ensure_line="$(grep -n 'ensure.root.or.sudo.reexec "\$@"' "${ROOT}/setup/cli/codex.sh" | tail -n1 | cut -d: -f1)"
codex_source_line="$(grep -n 'source.release.common' "${ROOT}/setup/cli/codex.sh" | tail -n1 | cut -d: -f1)"
if [[ -z "${codex_ensure_line}" || -z "${codex_source_line}" || "${codex_ensure_line}" -ge "${codex_source_line}" ]]; then
  echo "[validate.runtime][error] setup/cli/codex.sh must re-enter with sudo before sourcing release.common"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/codex.yml contract..."
if ! grep -q 'codex_node_install_scope' "${ROOT}/ansible/cli/codex.yml"; then
  echo "[validate.runtime][error] ansible/cli/codex.yml must define codex_node_install_scope"
  rc=1
fi
if ! grep -q 'codex_node_shared_nvm_dir' "${ROOT}/ansible/cli/codex.yml"; then
  echo "[validate.runtime][error] ansible/cli/codex.yml must define codex_node_shared_nvm_dir"
  rc=1
fi
if ! grep -q 'codex_nvm_dir_effective' "${ROOT}/ansible/cli/codex.yml"; then
  echo "[validate.runtime][error] ansible/cli/codex.yml must derive codex_nvm_dir_effective"
  rc=1
fi
if ! grep -q 'nvm use default' "${ROOT}/ansible/cli/codex.yml"; then
  echo "[validate.runtime][error] ansible/cli/codex.yml must activate the default Node runtime before Codex operations"
  rc=1
fi

echo "[validate.runtime] checking setup/autologin.sh runner contract..."
if ! bash -n "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"autologin.yml"' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must reference autologin.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_ENABLE' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_ENABLE"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_MODE' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_USER' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_USER"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_TTY' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_TTY"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_ACTION' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_ACTION"
  rc=1
fi
if ! grep -q 'ensure.root.or.sudo.reexec' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support sudo re-entry"
  rc=1
fi
if ! grep -q 'DEBIAN_AUTOLOGIN_SUDO_REEXEC' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support DEBIAN_AUTOLOGIN_SUDO_REEXEC"
  rc=1
fi
if ! grep -q 'preflight|apply|disable' "${ROOT}/setup/autologin.sh"; then
  echo "[validate.runtime][error] setup/autologin.sh must support preflight, apply, and disable modes"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/tauri.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"cli/node.yml"' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must reference cli/node.yml"
  rc=1
fi
if ! grep -q '"cli/tauri.yml"' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must reference cli/tauri.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_MODE' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support DEBIAN_CLI_TAURI_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_PROFILE' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support DEBIAN_CLI_TAURI_PROFILE"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_PROFILE:-runtime' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must default DEBIAN_CLI_TAURI_PROFILE to runtime"
  rc=1
fi
if ! grep -q 'preflight|apply|upgrade' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support preflight, apply, and upgrade modes"
  rc=1
fi
if ! grep -q 'runtime|build' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support runtime and build profiles"
  rc=1
fi
if ! grep -q 'setup/release.common.sh' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must reference setup/release.common.sh"
  rc=1
fi
if ! grep -q 'resolve.profile.defaults' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must compute runtime/build profile defaults"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_INVOKING_USER' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must preserve the invoking user across sudo re-entry"
  rc=1
fi
if ! grep -q 'tauri_invoking_user:' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must pass tauri_invoking_user into the Tauri playbook"
  rc=1
fi
if grep -n '^  DEPS=' "${ROOT}/setup/cli/tauri.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/cli/tauri.sh contains broken pasted one-liner"
  rc=1
fi
if grep -n '^  LI=' "${ROOT}/setup/cli/tauri.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/cli/tauri.sh contains broken pasted one-liner"
  rc=1
fi
if ! grep -q 'TAURI_NODE_MIN_MAJOR' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must define TAURI_NODE_MIN_MAJOR"
  rc=1
fi
if ! grep -q 'TAURI_NPM_MIN_MAJOR' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must define TAURI_NPM_MIN_MAJOR"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_NODE_INSTALL_SCOPE' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support DEBIAN_CLI_TAURI_NODE_INSTALL_SCOPE"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_NODE_SHARED_NVM_DIR' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must support DEBIAN_CLI_TAURI_NODE_SHARED_NVM_DIR"
  rc=1
fi
if ! grep -q 'resolve.node.install.effective' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must resolve effective Node install decisions"
  rc=1
fi
if ! grep -q 'TAURI_INSTALL_NODE_EFFECTIVE' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must define TAURI_INSTALL_NODE_EFFECTIVE"
  rc=1
fi
if ! grep -q 'TAURI_INSTALL_NODE_REQUESTED' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must define TAURI_INSTALL_NODE_REQUESTED"
  rc=1
fi
if ! grep -q 'DEBIAN_CLI_TAURI_CLI_METHOD:-npm' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must default DEBIAN_CLI_TAURI_CLI_METHOD to npm"
  rc=1
fi
if ! grep -q 'node_npm_min_major' "${ROOT}/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must pass node_npm_min_major to the Node feature"
  rc=1
fi
if search_regex 'codex' "${ROOT}/setup/cli/tauri.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/cli/tauri.sh must not install codex directly"
  rc=1
fi
require_contains "setup/cli/tauri.sh" 'ensure.root.or.sudo.reexec'
require_contains "setup/cli/tauri.sh" 'DEBIAN_CLI_TAURI_SUDO_REEXEC'
require_contains "setup/cli/tauri.sh" 'TAURI_SELF_URL'
require_contains "setup/cli/tauri.sh" 'sudo -v'
require_contains "setup/cli/tauri.sh" 'collect.sudo.env.args'
require_contains "setup/cli/tauri.sh" 'wget -qO- "$1" | bash -s -- "${@:2}"'
reject_contains "setup/cli/tauri.sh" 'TAURI_NODE_SYSTEM_SCOPE_OK'
reject_contains "setup/cli/tauri.sh" 'TAURI_NODE_SYSTEM_RESOLVED'
reject_contains "ansible/cli/node.yml" 'node_validate_non_root'
reject_contains "ansible/cli/tauri.yml" 'system_private_backing'
reject_contains "ansible/cli/tauri.yml" 'private_system_runtime_path'
reject_contains "ansible/cli/tauri.yml" 'setpriv --reuid=65534'

echo "[validate.runtime] checking setup/cli/startx.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"cli/startx.yml"' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must reference cli/startx.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_MODE' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_ENABLE' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_ENABLE"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_USER' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_USER"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_TTY' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_TTY"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_DISPLAY' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_DISPLAY"
  rc=1
fi
if ! grep -q 'preflight|apply|disable' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support preflight, apply, and disable modes"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/startx.sh feature vars contract..."
if ! grep -q 'DEBIAN_STARTX_OPENBOX_COMMAND' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_OPENBOX_COMMAND"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_XINITRC_PATH' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_XINITRC_PATH"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_XSESSION_HOOK_DIR' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_XSESSION_HOOK_DIR"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_WRAPPER_PATH' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_WRAPPER_PATH"
  rc=1
fi
if ! grep -q 'DEBIAN_STARTX_SERVER_ARGS' "${ROOT}/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] setup/cli/startx.sh must support DEBIAN_STARTX_SERVER_ARGS"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/x11.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"cli/x11.yml"' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must reference cli/x11.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_X11_MODE' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must support DEBIAN_X11_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_X11_ENABLE' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must support DEBIAN_X11_ENABLE"
  rc=1
fi
if ! grep -q 'DEBIAN_X11_PACKAGES' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must support DEBIAN_X11_PACKAGES"
  rc=1
fi
if ! grep -q 'DEBIAN_X11_RUNTIME_FACTS_PATH' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must support DEBIAN_X11_RUNTIME_FACTS_PATH"
  rc=1
fi
if ! grep -q 'preflight|apply|disable' "${ROOT}/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] setup/cli/x11.sh must support preflight, apply, and disable modes"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/openbox.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"cli/openbox.yml"' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must reference cli/openbox.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_OPENBOX_MODE' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must support DEBIAN_OPENBOX_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_OPENBOX_ENABLE' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must support DEBIAN_OPENBOX_ENABLE"
  rc=1
fi
if ! grep -q 'DEBIAN_OPENBOX_USER' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must support DEBIAN_OPENBOX_USER"
  rc=1
fi
if ! grep -q 'DEBIAN_OPENBOX_FULLSCREEN' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must support DEBIAN_OPENBOX_FULLSCREEN"
  rc=1
fi
if ! grep -q 'preflight|apply|disable' "${ROOT}/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] setup/cli/openbox.sh must support preflight, apply, and disable modes"
  rc=1
fi

echo "[validate.runtime] checking setup/cli/touchscreen.sh runner contract..."
if ! bash -n "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must pass bash -n"
  rc=1
fi
if ! grep -q '"cli/touchscreen.yml"' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must reference cli/touchscreen.yml"
  rc=1
fi
if ! grep -q 'GROUP_VARS_FILES=(' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must define GROUP_VARS_FILES"
  rc=1
fi
if ! grep -q 'ensure.local.ansible' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must use ensure.local.ansible"
  rc=1
fi
if ! grep -q '/tmp/ansible/debian' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must use neutral /tmp/ansible/debian cache paths"
  rc=1
fi
if ! grep -q 'DEBIAN_TOUCHSCREEN_MODE' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must support DEBIAN_TOUCHSCREEN_MODE"
  rc=1
fi
if ! grep -q 'DEBIAN_TOUCHSCREEN_ENABLE' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must support DEBIAN_TOUCHSCREEN_ENABLE"
  rc=1
fi
if ! grep -q 'DEBIAN_TOUCHSCREEN_RUNTIME_FACTS_PATH' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must support DEBIAN_TOUCHSCREEN_RUNTIME_FACTS_PATH"
  rc=1
fi
if ! grep -q 'DEBIAN_TOUCHSCREEN_PACKAGES' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must support DEBIAN_TOUCHSCREEN_PACKAGES"
  rc=1
fi
if ! grep -q 'preflight|apply|disable' "${ROOT}/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] setup/cli/touchscreen.sh must support preflight, apply, and disable modes"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/startx.yml contract..."
if ! grep -q 'startx_enable: true' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define default startx_enable"
  rc=1
fi
if ! grep -q 'startx_mode: "apply"' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must default startx_mode to apply"
  rc=1
fi
if ! grep -q 'startx_user: "app"' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must default startx_user to app"
  rc=1
fi
if ! grep -q 'startx_tty: "tty1"' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must default startx_tty to tty1"
  rc=1
fi
if ! grep -q 'startx_display: ":0"' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must default startx_display to :0"
  rc=1
fi
if ! grep -q 'startx_install_packages' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_install_packages"
  rc=1
fi
if ! grep -q 'startx_manage_xwrapper' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_manage_xwrapper"
  rc=1
fi
if ! grep -q 'startx_wrapper_path' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_wrapper_path"
  rc=1
fi
if ! grep -q 'startx_xinitrc_path' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_xinitrc_path"
  rc=1
fi
if ! grep -q 'startx_xsession_hook_dir' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_xsession_hook_dir"
  rc=1
fi
if ! grep -q 'xwrapper_config_path' "${ROOT}/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] ansible/cli/startx.yml must define startx_xwrapper_config_path"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/x11.yml contract..."
if ! grep -q 'x11_enable:' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must define x11_enable"
  rc=1
fi
if ! grep -q 'x11_mode: "apply"' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must default x11_mode to apply"
  rc=1
fi
if ! grep -q 'x11_install_packages' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must define x11_install_packages"
  rc=1
fi
if ! grep -q 'x11_packages:' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must define x11_packages"
  rc=1
fi
if ! grep -q 'xserver-xorg' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must include xserver-xorg"
  rc=1
fi
if ! grep -q 'wmctrl' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must include wmctrl"
  rc=1
fi
if ! grep -q 'x11_runtime_facts_path' "${ROOT}/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] ansible/cli/x11.yml must define x11_runtime_facts_path"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/openbox.yml contract..."
if ! grep -q 'openbox_enable:' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_enable"
  rc=1
fi
if ! grep -q 'openbox_mode: "apply"' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must default openbox_mode to apply"
  rc=1
fi
if ! grep -q 'openbox_user:' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_user"
  rc=1
fi
if ! grep -q 'openbox_session_command' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_session_command"
  rc=1
fi
if ! grep -q 'openbox_packages:' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_packages"
  rc=1
fi
if ! grep -q 'openbox_fullscreen_helper' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_fullscreen_helper"
  rc=1
fi
if ! grep -q 'openbox_runtime_facts_path' "${ROOT}/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] ansible/cli/openbox.yml must define openbox_runtime_facts_path"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/touchscreen.yml contract..."
if ! grep -q 'touchscreen_enable:' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_enable"
  rc=1
fi
if ! grep -q 'touchscreen_mode: "apply"' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must default touchscreen_mode to apply"
  rc=1
fi
if ! grep -q 'touchscreen_user:' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_user"
  rc=1
fi
if ! grep -q 'touchscreen_match:' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_match"
  rc=1
fi
if ! grep -q 'touchscreen_install_packages' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_install_packages"
  rc=1
fi
if ! grep -q 'touchscreen_config_file' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_config_file"
  rc=1
fi
if ! grep -q 'touchscreen_apply_script_path' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_apply_script_path"
  rc=1
fi
if ! grep -q 'touchscreen_runtime_facts_path' "${ROOT}/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] ansible/cli/touchscreen.yml must define touchscreen_runtime_facts_path"
  rc=1
fi


echo "[validate.runtime] checking Tauri playbook YAML syntax..."
for f in \
  "${ROOT}/ansible/autologin.yml" \
  "${ROOT}/static/ansible/autologin.yml" \
  "${ROOT}/ansible/cli/startx.yml" \
  "${ROOT}/static/ansible/cli/startx.yml" \
  "${ROOT}/ansible/cli/x11.yml" \
  "${ROOT}/static/ansible/cli/x11.yml" \
  "${ROOT}/ansible/cli/openbox.yml" \
  "${ROOT}/static/ansible/cli/openbox.yml" \
  "${ROOT}/ansible/cli/touchscreen.yml" \
  "${ROOT}/static/ansible/cli/touchscreen.yml" \
  "${ROOT}/ansible/cli/tauri.yml" \
  "${ROOT}/static/ansible/cli/tauri.yml" \
  "${ROOT}/ansible/cli/node.yml" \
  "${ROOT}/static/ansible/cli/node.yml"; do
  if ! validate_yaml_file "${f}"; then
    rc=1
  fi
  if ! validate_shell_payloads "${f}"; then
    rc=1
  fi
done

if ! cmp -s "${ROOT}/ansible/cli/tauri.yml" "${ROOT}/static/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/tauri.yml is out of sync with ansible/cli/tauri.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/cli/startx.yml" "${ROOT}/static/ansible/cli/startx.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/startx.yml is out of sync with ansible/cli/startx.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/cli/x11.yml" "${ROOT}/static/ansible/cli/x11.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/x11.yml is out of sync with ansible/cli/x11.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/cli/openbox.yml" "${ROOT}/static/ansible/cli/openbox.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/openbox.yml is out of sync with ansible/cli/openbox.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/cli/touchscreen.yml" "${ROOT}/static/ansible/cli/touchscreen.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/touchscreen.yml is out of sync with ansible/cli/touchscreen.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/autologin.yml" "${ROOT}/static/ansible/autologin.yml"; then
  echo "[validate.runtime][error] static/ansible/autologin.yml is out of sync with ansible/autologin.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/autologin.sh" "${ROOT}/static/setup/autologin.sh"; then
  echo "[validate.runtime][error] static/setup/autologin.sh is out of sync with setup/autologin.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/autologin.sh" "${ROOT}/static/setup/autologin"; then
  echo "[validate.runtime][error] static/setup/autologin is out of sync with setup/autologin.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/tauri.sh" "${ROOT}/static/setup/cli/tauri.sh"; then
  echo "[validate.runtime][error] static/setup/cli/tauri.sh is out of sync with setup/cli/tauri.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/tauri.sh" "${ROOT}/static/setup/cli/tauri"; then
  echo "[validate.runtime][error] static/setup/cli/tauri is out of sync with setup/cli/tauri.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/startx.sh" "${ROOT}/static/setup/cli/startx.sh"; then
  echo "[validate.runtime][error] static/setup/cli/startx.sh is out of sync with setup/cli/startx.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/startx.sh" "${ROOT}/static/setup/cli/startx"; then
  echo "[validate.runtime][error] static/setup/cli/startx is out of sync with setup/cli/startx.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/x11.sh" "${ROOT}/static/setup/cli/x11.sh"; then
  echo "[validate.runtime][error] static/setup/cli/x11.sh is out of sync with setup/cli/x11.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/x11.sh" "${ROOT}/static/setup/cli/x11"; then
  echo "[validate.runtime][error] static/setup/cli/x11 is out of sync with setup/cli/x11.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/openbox.sh" "${ROOT}/static/setup/cli/openbox.sh"; then
  echo "[validate.runtime][error] static/setup/cli/openbox.sh is out of sync with setup/cli/openbox.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/openbox.sh" "${ROOT}/static/setup/cli/openbox"; then
  echo "[validate.runtime][error] static/setup/cli/openbox is out of sync with setup/cli/openbox.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/touchscreen.sh" "${ROOT}/static/setup/cli/touchscreen.sh"; then
  echo "[validate.runtime][error] static/setup/cli/touchscreen.sh is out of sync with setup/cli/touchscreen.sh"
  rc=1
fi
if ! cmp -s "${ROOT}/setup/cli/touchscreen.sh" "${ROOT}/static/setup/cli/touchscreen"; then
  echo "[validate.runtime][error] static/setup/cli/touchscreen is out of sync with setup/cli/touchscreen.sh"
  rc=1
fi

if ! cmp -s "${ROOT}/ansible/cli/node.yml" "${ROOT}/static/ansible/cli/node.yml"; then
  echo "[validate.runtime][error] static/ansible/cli/node.yml is out of sync with ansible/cli/node.yml"
  rc=1
fi
if ! cmp -s "${ROOT}/ansible/group_vars/debian.yml" "${ROOT}/static/ansible/group_vars/debian.yml"; then
  echo "[validate.runtime][error] static/ansible/group_vars/debian.yml is out of sync with ansible/group_vars/debian.yml"
  rc=1
fi

echo "[validate.runtime] checking ansible/autologin.yml contract..."
if ! grep -q 'autologin_enable' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_enable"
  rc=1
fi
if ! grep -q 'autologin_mode' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_mode"
  rc=1
fi
if ! grep -q 'autologin_user' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_user"
  rc=1
fi
if ! grep -q 'autologin_tty' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_tty"
  rc=1
fi
if ! grep -q 'autologin_action' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_action"
  rc=1
fi
if ! grep -q 'autologin_command' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_command"
  rc=1
fi
if ! grep -q 'autologin_runtime_facts_path' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must define autologin_runtime_facts_path"
  rc=1
fi
if ! grep -q 'getty@tty1.service.d' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must manage getty@tty1.service.d by default"
  rc=1
fi
if ! grep -q -- '--autologin' "${ROOT}/ansible/autologin.yml"; then
  echo "[validate.runtime][error] ansible/autologin.yml must configure agetty --autologin"
  rc=1
fi

echo "[validate.runtime] checking ansible/cli/tauri.yml contract..."
if ! grep -q 'tauri_mode: "apply"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must default tauri_mode to apply"
  rc=1
fi
if ! grep -q 'tauri_profile: "runtime"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must default tauri_profile to runtime"
  rc=1
fi
if ! grep -q 'tauri_cli_method: "npm"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must default tauri_cli_method to npm"
  rc=1
fi
if ! grep -q 'libwebkit2gtk-4.1-dev' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include libwebkit2gtk-4.1-dev dependency"
  rc=1
fi
if ! grep -q 'libayatana-appindicator3-dev' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include libayatana-appindicator3-dev dependency"
  rc=1
fi
if ! grep -q 'librsvg2-dev' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include librsvg2-dev dependency"
  rc=1
fi
if ! grep -q 'xdg-utils' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include xdg-utils runtime dependency"
  rc=1
fi
if ! grep -q 'libwebkit2gtk-4.1-0' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include libwebkit2gtk-4.1-0 runtime dependency"
  rc=1
fi
if ! grep -q 'libgtk-3-0' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must include libgtk-3-0 runtime dependency"
  rc=1
fi
if ! grep -q 'tauri_runtime_facts_path' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must write Tauri runtime facts"
  rc=1
fi
if ! grep -q 'tauri_invoking_home_effective' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must resolve the invoking user home path"
  rc=1
fi
if ! grep -q '/.npm' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must repair invoking user .npm ownership"
  rc=1
fi
if ! grep -q '/etc/ansible/debian/facts/cli.tauri.yml' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must write /etc/ansible/debian/facts/cli.tauri.yml"
  rc=1
fi
if ! grep -q 'tauri_install_rust' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must support explicit Rust install toggle"
  rc=1
fi
if ! grep -q 'tauri_install_rust_effective' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must compute tauri_install_rust_effective"
  rc=1
fi
if ! grep -q 'tauri_install_cli_effective' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must compute tauri_install_cli_effective"
  rc=1
fi
if ! grep -q 'tauri_rust_create_system_symlinks' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_rust_create_system_symlinks"
  rc=1
fi
if ! grep -q 'tauri_rust_profile_hook_path' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_rust_profile_hook_path"
  rc=1
fi
if ! grep -q 'tauri_rust_shell_validate' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_rust_shell_validate"
  rc=1
fi
if ! grep -q 'tauri_rust_env_effective' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must derive tauri_rust_env_effective"
  rc=1
fi
if ! grep -q 'tauri_rust_bin_dir_effective' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must derive tauri_rust_bin_dir_effective"
  rc=1
fi
if ! grep -q 'for exe in rustc cargo rustup' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must manage rustc/cargo/rustup symlink loop"
  rc=1
fi
if ! grep -Eq '/usr/local/bin|tauri_rust_symlink_dir' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define system symlink directory for Rust"
  rc=1
fi
if ! grep -q 'tauri_rust_symlink_dir: "/usr/local/bin"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must manage shell-visible rustc path"
  rc=1
fi
if ! grep -q 'tauri_rust_symlink_dir: "/usr/local/bin"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must manage shell-visible cargo path"
  rc=1
fi
if ! grep -q 'tauri_rust_symlink_dir: "/usr/local/bin"' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must manage shell-visible rustup path"
  rc=1
fi
if ! grep -q 'tauri_rust_min_version' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_rust_min_version"
  rc=1
fi
if ! grep -q 'tauri_cli_min_version' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_cli_min_version"
  rc=1
fi
if ! grep -q 'tauri_node_install_scope' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must define tauri_node_install_scope"
  rc=1
fi
if ! grep -q 'node_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit node_ok probe data"
  rc=1
fi
if ! grep -q 'npm_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit npm_ok probe data"
  rc=1
fi
if ! grep -q 'node_scope_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit node_scope_ok probe data"
  rc=1
fi
if ! grep -q 'node_runtime_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit node_runtime_ok probe data"
  rc=1
fi
if ! grep -q 'node_realpath' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must capture node_realpath probe data"
  rc=1
fi
if ! grep -q 'rustc_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit rustc_ok probe data"
  rc=1
fi
if ! grep -q 'cargo_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit cargo_ok probe data"
  rc=1
fi
if ! grep -q 'rustc_shell_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit rustc_shell_ok probe data"
  rc=1
fi
if ! grep -q 'cargo_shell_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit cargo_shell_ok probe data"
  rc=1
fi
if ! grep -q 'rustup_shell_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit rustup_shell_ok probe data"
  rc=1
fi
if ! grep -q 'tauri_cli_ok' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must emit tauri_cli_ok probe data"
  rc=1
fi
if ! grep -q 'shell_visible:' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml facts must include shell_visible section"
  rc=1
fi
if ! grep -q 'shell_paths:' "${ROOT}/ansible/cli/tauri.yml"; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml facts must include shell_paths section"
  rc=1
fi
if search_regex 'npm create tauri-app|npx tauri init' "${ROOT}/ansible/cli/tauri.yml" >/dev/null; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must not scaffold or initialize app source"
  rc=1
fi
if search_regex 'npm exec tauri -- --version' "${ROOT}/ansible/cli/tauri.yml" >/dev/null; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must not use npm exec tauri -- --version fallback"
  rc=1
fi
if search_regex 'Vue|Vite|Webpack|Phaser|ThreeJS|database|camera.py|hardware.py' "${ROOT}/ansible/cli/tauri.yml" >/dev/null; then
  echo "[validate.runtime][error] ansible/cli/tauri.yml must stay platform-only and not include app/framework sidecars"
  rc=1
fi
if search_regex '(^|[^[:alnum:]_])rust --version([^[:alnum:]_]|$)' \
  "${ROOT}/ansible/cli/tauri.yml" \
  "${ROOT}/setup/cli/tauri.sh" >/dev/null; then
  echo "[validate.runtime][error] validation and examples must check rustc/cargo/rustup, not rust"
  rc=1
fi
if grep -qx 'cli/tauri.yml' "${ROOT}/ansible/install.playbooks.txt"; then
  echo "[validate.runtime][error] ansible/install.playbooks.txt must not include cli/tauri.yml"
  rc=1
fi
if search_regex 'tauri' "${ROOT}/setup/hardware.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/hardware.sh must not include tauri feature logic"
  rc=1
fi
if search_regex 'tauri' "${ROOT}/setup/cli/codex.sh" >/dev/null; then
  echo "[validate.runtime][error] setup/cli/codex.sh must not include tauri feature logic"
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
if ! grep -q 'ensure.root.or.sudo.reexec' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must support sudo re-entry"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_SUDO_REEXEC' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must support DEBIAN_HARDWARE_SUDO_REEXEC"
  rc=1
fi
if ! grep -q 'DEBIAN_HARDWARE_SELF_URL' "${ROOT}/setup/hardware.sh"; then
  echo "[validate.runtime][error] setup/hardware.sh must support DEBIAN_HARDWARE_SELF_URL"
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
if search_regex 'proxmox|pveversion|vmbr|pct |qm |/etc/ansible/proxmox|devs-guide.github.io/proxmox' \
  "${ROOT}/setup/bootstrap.sh" \
  "${ROOT}/setup/debian.sh" \
  "${ROOT}/setup/metal.sh" \
  "${ROOT}/setup/hardware.sh" \
  "${ROOT}/setup/autologin.sh" \
  "${ROOT}/setup/cli/node.sh" \
  "${ROOT}/setup/cli/x11.sh" \
  "${ROOT}/setup/cli/openbox.sh" \
  "${ROOT}/setup/cli/touchscreen.sh" \
  "${ROOT}/setup/release.common.sh" \
  "${ROOT}/setup/cli/codex.sh" \
  "${ROOT}/setup/cli/startx.sh" \
  "${ROOT}/setup/cli/tauri.sh" \
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
