#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-https://devs-guide.github.io/debian}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
DOCS_RENDER_DIR="${TMPDIR}/rendered-docs"
rc=0

base_without_scheme="${BASE_URL#*://}"
if [[ "${base_without_scheme}" == */* ]]; then
  DOCS_SITE_ROOT="/${base_without_scheme#*/}"
else
  DOCS_SITE_ROOT="/"
fi
DOCS_SITE_ROOT="/${DOCS_SITE_ROOT#/}"
DOCS_SITE_ROOT="${DOCS_SITE_ROOT%/}"
[[ -n "${DOCS_SITE_ROOT}" ]] || DOCS_SITE_ROOT="/"

FILES=(
  "index.html:${DOCS_RENDER_DIR}/index.html"
  "assets/docs/site.css:${DOCS_RENDER_DIR}/assets/docs/site.css"
  "cli/index.html:${DOCS_RENDER_DIR}/cli/index.html"
  "cli/nvidia/index.html:${DOCS_RENDER_DIR}/cli/nvidia/index.html"
  "cli/nvlink/index.html:${DOCS_RENDER_DIR}/cli/nvlink/index.html"
  "setup/index.html:${DOCS_RENDER_DIR}/setup/index.html"
  "setup/bootstrap/index.html:${DOCS_RENDER_DIR}/setup/bootstrap/index.html"
  "setup/runner-common/index.html:${DOCS_RENDER_DIR}/setup/runner-common/index.html"
  "ansible/index.html:${DOCS_RENDER_DIR}/ansible/index.html"
  "actions/index.html:${DOCS_RENDER_DIR}/actions/index.html"
  "actions/build-docs/index.html:${DOCS_RENDER_DIR}/actions/build-docs/index.html"
  "actions/publish/index.html:${DOCS_RENDER_DIR}/actions/publish/index.html"
  "actions/validate/runtime/index.html:${DOCS_RENDER_DIR}/actions/validate/runtime/index.html"
  "actions/validate/pages/index.html:${DOCS_RENDER_DIR}/actions/validate/pages/index.html"
  "actions/test/sudo-access/index.html:${DOCS_RENDER_DIR}/actions/test/sudo-access/index.html"
  "actions/test/runner-staging/index.html:${DOCS_RENDER_DIR}/actions/test/runner-staging/index.html"
  "actions/test/nvidia-facts/index.html:${DOCS_RENDER_DIR}/actions/test/nvidia-facts/index.html"
  "kiosk/index.html:${DOCS_RENDER_DIR}/kiosk/index.html"
  "kiosk/reference/index.html:${DOCS_RENDER_DIR}/kiosk/reference/index.html"
  "history/index.html:${DOCS_RENDER_DIR}/history/index.html"
  "history/www.index.legacy.html:${DOCS_RENDER_DIR}/history/www.index.legacy.html"
  "setup/bootstrap.sh:setup/bootstrap.sh"
  "setup/debian.sh:setup/debian.sh"
  "setup/metal.sh:setup/metal.sh"
  "setup/hardware.sh:setup/hardware.sh"
  "setup/autologin.sh:setup/autologin.sh"
  "setup/runner.common.sh:setup/runner.common.sh"
  "setup/release.common.sh:setup/release.common.sh"
  "setup/cli/node.sh:setup/cli/node.sh"
  "setup/cli/kiosk.app.sh:setup/cli/kiosk.app.sh"
  "setup/cli/x11.sh:setup/cli/x11.sh"
  "setup/cli/openbox.sh:setup/cli/openbox.sh"
  "setup/cli/touchscreen.sh:setup/cli/touchscreen.sh"
  "setup/cli/codex.sh:setup/cli/codex.sh"
  "setup/cli/startx.sh:setup/cli/startx.sh"
  "setup/cli/tauri.sh:setup/cli/tauri.sh"
  "setup/cli/nvidia.sh:setup/cli/nvidia.sh"
  "setup/cli/nvlink.sh:setup/cli/nvlink.sh"
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
  "ansible/cli/nvlink.yml:ansible/cli/nvlink.yml"
  "ansible/tasks/nvidia.normalize-observations.yml:ansible/tasks/nvidia.normalize-observations.yml"
  "ansible/files/nvlink/nvidia-cuda-smoke.cu:ansible/files/nvlink/nvidia-cuda-smoke.cu"
  "ansible/files/nvlink/nvidia-p2p-verify.cu:ansible/files/nvlink/nvidia-p2p-verify.cu"
  "ansible/files/nvlink/nvidia-topology-parser.py:ansible/files/nvlink/nvidia-topology-parser.py"
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
echo "[validate.pages] render canonical docs with site root: ${DOCS_SITE_ROOT}"

if ! DOCS_SITE_ROOT="${DOCS_SITE_ROOT}" bash "${ROOT}/actions/build.docs.sh" \
  --source "${ROOT}/docs" \
  --output "${DOCS_RENDER_DIR}" \
  --site-root "${DOCS_SITE_ROOT}"; then
  echo "[validate.pages][error] could not render canonical documentation for comparison"
  exit 1
fi

for entry in "${FILES[@]}"; do
  remote_path="${entry%%:*}"
  local_path="${entry#*:}"
  dest="${TMPDIR}/published/${remote_path}"
  mkdir -p "$(dirname "${dest}")"

  url="${BASE_URL}/${remote_path}"
  echo "[validate.pages] fetch ${url}"
  if ! curl -fsSL "${url}" -o "${dest}"; then
    echo "[validate.pages][error] failed to fetch ${url}"
    rc=1
    continue
  fi

  if [[ "${local_path}" = /* ]]; then
    local_file="${local_path}"
  else
    local_file="${ROOT}/${local_path}"
  fi

  if ! diff -u "${local_file}" "${dest}" >/dev/null; then
    echo "[validate.pages][diff] ${local_path} differs from published ${url}"
    diff -u "${local_file}" "${dest}" || true
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
check_setup_feature_refs "setup/cli/nvlink.sh"
check_setup_feature_refs "setup/hardware.sh"
check_setup_feature_refs "setup/autologin.sh"

check_nvidia_runner_runtime_support() {
  local remote_runner="${TMPDIR}/published/setup/cli/nvidia.sh"

  if [[ ! -s "${remote_runner}" ]]; then
    echo "[validate.pages][error] published NVIDIA runner was not fetched: ${remote_runner}"
    rc=1
    return
  fi
  for reference in packages.yml tasks/nvidia.normalize-observations.yml; do
    if ! grep -Fq "${reference}" "${remote_runner}"; then
      echo "[validate.pages][error] published NVIDIA runner must reference ${reference}"
      rc=1
    fi
  done
}

check_nvidia_runner_runtime_support

check_nvlink_runner_runtime_support() {
  local remote_runner="${TMPDIR}/published/setup/cli/nvlink.sh"

  if [[ ! -s "${remote_runner}" ]]; then
    echo "[validate.pages][error] published NVLink runner was not fetched: ${remote_runner}"
    rc=1
    return
  fi
  for reference in packages.yml tasks/nvidia.normalize-observations.yml files/nvlink/nvidia-cuda-smoke.cu files/nvlink/nvidia-p2p-verify.cu files/nvlink/nvidia-topology-parser.py; do
    if ! grep -Fq "${reference}" "${remote_runner}"; then
      echo "[validate.pages][error] published NVLink runner must reference ${reference}"
      rc=1
    fi
  done
}

check_nvlink_runner_runtime_support

exit "${rc}"
