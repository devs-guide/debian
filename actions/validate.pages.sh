#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-https://devs-guide.github.io/debian}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
rc=0

FILES=(
  "index.html:www/index.html"
  "setup/bootstrap.sh:setup/bootstrap.sh"
  "setup/debian.sh:setup/debian.sh"
  "setup/metal.sh:setup/metal.sh"
  "setup/hardware.sh:setup/hardware.sh"
  "setup/hardware:setup/hardware.sh"
  "setup/autologin.sh:setup/autologin.sh"
  "setup/autologin:setup/autologin.sh"
  "setup/release.common.sh:setup/release.common.sh"
  "setup/cli/node.sh:setup/cli/node.sh"
  "setup/cli/node:setup/cli/node.sh"
  "setup/cli/kiosk.app.sh:setup/cli/kiosk.app.sh"
  "setup/cli/kiosk.app:setup/cli/kiosk.app.sh"
  "setup/cli/x11.sh:setup/cli/x11.sh"
  "setup/cli/x11:setup/cli/x11.sh"
  "setup/cli/openbox.sh:setup/cli/openbox.sh"
  "setup/cli/openbox:setup/cli/openbox.sh"
  "setup/cli/touchscreen.sh:setup/cli/touchscreen.sh"
  "setup/cli/touchscreen:setup/cli/touchscreen.sh"
  "setup/cli/codex.sh:setup/cli/codex.sh"
  "setup/cli/startx.sh:setup/cli/startx.sh"
  "setup/cli/startx:setup/cli/startx.sh"
  "setup/cli/tauri.sh:setup/cli/tauri.sh"
  "setup/cli/tauri:setup/cli/tauri.sh"
  "setup/cli/nvidia.sh:setup/cli/nvidia.sh"
  "setup/cli/nvidia:setup/cli/nvidia.sh"
  "readme.md:readme.md"
  "ansible/install.playbooks.txt:ansible/install.playbooks.txt"
  "ansible/bootstrap.yml:ansible/bootstrap.yml"
  "ansible/install.packages.yml:ansible/install.packages.yml"
  "ansible/packages.yml:ansible/packages.yml"
  "ansible/network.yml:ansible/network.yml"
  "ansible/users.yml:ansible/users.yml"
  "ansible/lan.yml:ansible/lan.yml"
  "ansible/ssh.yml:ansible/ssh.yml"
  "ansible/sources.yml:ansible/sources.yml"
  "ansible/cli/tauri.yml:ansible/cli/tauri.yml"
  "ansible/cli/nvidia.yml:ansible/cli/nvidia.yml"
  "ansible/cli/x11.yml:ansible/cli/x11.yml"
  "ansible/cli/openbox.yml:ansible/cli/openbox.yml"
  "ansible/cli/touchscreen.yml:ansible/cli/touchscreen.yml"
  "ansible/cli/startx.yml:ansible/cli/startx.yml"
  "ansible/autologin.yml:ansible/autologin.yml"
  "ansible/group_vars/all.yml:ansible/group_vars/all.yml"
  "ansible/group_vars/debian.yml:ansible/group_vars/debian.yml"
  "ansible/group_vars/trixie.yml:ansible/group_vars/trixie.yml"
  "ansible/group_vars/buster.yml:ansible/group_vars/buster.yml"
)

echo "[validate.pages] using BASE_URL=${BASE_URL}"
echo "[validate.pages] temp dir: ${TMPDIR}"

for entry in "${FILES[@]}"; do
  remote_path="${entry%%:*}"
  local_path="${entry#*:}"
  dest="${TMPDIR}/${remote_path}"
  mkdir -p "$(dirname "${dest}")"

  url="${BASE_URL}/${remote_path}"
  echo "[validate.pages] fetch ${url}"
  if ! curl -fsSL "${url}" -o "${dest}"; then
    echo "[validate.pages][error] failed to fetch ${url}"
    rc=1
    continue
  fi

  if ! diff -u "${ROOT}/${local_path}" "${dest}" >/dev/null; then
    echo "[validate.pages][diff] ${local_path} differs from published ${url}"
    diff -u "${ROOT}/${local_path}" "${dest}" || true
    rc=1
  else
    echo "[validate.pages][ok] ${local_path} matches published ${url}"
  fi
done

check_setup_feature_refs() {
  local runner_rel="$1"
  local runner_path="${ROOT}/${runner_rel}"
  local feature_ref
  local -a refs=()

  while IFS= read -r feature_ref; do
    [[ -n "${feature_ref}" ]] || continue
    refs+=("${feature_ref}")
  done < <(
    sed -n '/^[[:space:]]*FEATURE_PLAYBOOKS=(/,/^[[:space:]]*)/p' "${runner_path}" \
      | grep -Eo '"[^"]+"' \
      | tr -d '"'
  )

  if ((${#refs[@]} == 0)); then
    echo "[validate.pages][error] ${runner_rel} has empty or missing FEATURE_PLAYBOOKS array"
    rc=1
    return
  fi

  for feature_ref in "${refs[@]}"; do
    local local_playbook="${ROOT}/ansible/${feature_ref}"
    local remote_playbook="ansible/${feature_ref}"
    local tmp_playbook="${TMPDIR}/${remote_playbook}"
    local playbook_url="${BASE_URL}/${remote_playbook}"

    if [[ ! -f "${local_playbook}" ]]; then
      echo "[validate.pages][error] ${runner_rel} references missing local playbook: ansible/${feature_ref}"
      rc=1
      continue
    fi

    mkdir -p "$(dirname "${tmp_playbook}")"
    echo "[validate.pages] fetch ${playbook_url}"
    if ! curl -fsSL "${playbook_url}" -o "${tmp_playbook}"; then
      echo "[validate.pages][error] failed to fetch ${playbook_url}"
      rc=1
      continue
    fi

    if ! diff -u "${local_playbook}" "${tmp_playbook}" >/dev/null; then
      echo "[validate.pages][diff] ansible/${feature_ref} differs from published ${playbook_url}"
      diff -u "${local_playbook}" "${tmp_playbook}" || true
      rc=1
    else
      echo "[validate.pages][ok] ansible/${feature_ref} matches published ${playbook_url}"
    fi
  done
}

check_playlist_refs() {
  local playlist_path="ansible/install.playbooks.txt"
  local tmp_playlist="${TMPDIR}/${playlist_path}"
  mkdir -p "$(dirname "${tmp_playlist}")"

  echo "[validate.pages] fetch ${BASE_URL}/${playlist_path}"
  if ! curl -fsSL "${BASE_URL}/${playlist_path}" -o "${tmp_playlist}"; then
    echo "[validate.pages][error] failed to fetch ${BASE_URL}/${playlist_path}"
    rc=1
    return
  fi

  while IFS= read -r ref; do
    [[ -n "${ref}" ]] || continue
    [[ "${ref}" =~ ^[[:space:]]*# ]] && continue
    if [[ ! -f "${ROOT}/ansible/${ref}" ]]; then
      echo "[validate.pages][error] playlist entry missing locally: ansible/${ref}"
      rc=1
      continue
    fi

    local remote_playbook="ansible/${ref}"
    local tmp_playbook="${TMPDIR}/${remote_playbook}"
    mkdir -p "$(dirname "${tmp_playbook}")"
    echo "[validate.pages] fetch ${BASE_URL}/${remote_playbook}"
    if ! curl -fsSL "${BASE_URL}/${remote_playbook}" -o "${tmp_playbook}"; then
      echo "[validate.pages][error] failed to fetch ${BASE_URL}/${remote_playbook}"
      rc=1
      continue
    fi
  done < <(sed 's/[[:space:]]*$//' "${ROOT}/${playlist_path}" | grep -vE '^[[:space:]]*(#|$)')
}

check_playlist_refs
check_setup_feature_refs "setup/cli/node.sh"
check_setup_feature_refs "setup/cli/kiosk.app.sh"
check_setup_feature_refs "setup/cli/codex.sh"
check_setup_feature_refs "setup/cli/startx.sh"
check_setup_feature_refs "setup/cli/tauri.sh"
check_setup_feature_refs "setup/cli/nvidia.sh"
check_setup_feature_refs "setup/hardware.sh"
check_setup_feature_refs "setup/autologin.sh"

exit "${rc}"
