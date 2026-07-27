#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.llm-source-contract"
NETWORK_VERIFY="${LLM_SOURCE_NETWORK_VERIFY:-0}"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "${TEST_PARENT%/}/test.llm-source-contract.XXXXXX")"
rc=0

# shellcheck source=actions/lib/contracts.sh
source "${ROOT}/actions/lib/contracts.sh"

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && "${TEST_ROOT}" == "${TEST_PARENT%/}/test.llm-source-contract."* ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

echo "[${ACTION_LABEL}] checking reviewed llama.cpp and KTransformers source contracts..."

for file in \
  setup/cli/llm/llamacpp.sh \
  setup/cli/llm/ktransformers.sh \
  ansible/cli/llm/llamacpp.yml \
  ansible/cli/llm/ktransformers.yml \
  ansible/files/llm/source-profile.py \
  ansible/files/llm/llamacpp/compatibility-matrix.yml \
  ansible/files/llm/ktransformers/compatibility-matrix.yml \
  docs/cli/llm/llamacpp/readme.md \
  docs/cli/llm/ktransformers/readme.md; do
  require_file "${file}"
done

require_shell_syntax "setup/cli/llm/llamacpp.sh"
require_shell_syntax "setup/cli/llm/ktransformers.sh"

for runner in setup/cli/llm/llamacpp.sh setup/cli/llm/ktransformers.sh; do
  for marker in \
    '--matrix-profile=' \
    '--repository-url=' \
    '--release=' \
    '--commit=' \
    'runner.ensure.privileged.session' \
    'runner.prepare.ansible.feature' \
    'validate.reviewed.source' \
    'stage.reviewed.source'; do
    require_contains "${runner}" "${marker}"
  done
  reject_regex "${runner}" 'https://[^[:space:]]+@'
  reject_regex "${runner}" 'git[[:space:]]+clone[^#]*(main|master|latest)'
done

require_contains \
  "setup/cli/llm/llamacpp.sh" \
  '--commit=FULL_40_CHARACTER_SHA'
require_contains \
  "setup/cli/llm/ktransformers.sh" \
  '--commit=FULL_40_CHARACTER_SHA'
require_contains \
  "setup/cli/llm/ktransformers.sh" \
  '--sglang-commit=FULL_40_CHARACTER_SHA'

for marker in \
  '--sglang-repository-url=' \
  '--sglang-commit=' \
  '--allow-online-dependencies' \
  'stage.reviewed.sources' \
  'sha256sum'; do
  require_contains "setup/cli/llm/ktransformers.sh" "${marker}"
done

for marker in \
  'Reviewed apply example:' \
  'Remote local-model smoke example:' \
  '--source-dir=/opt/src/llamacpp/b10075-icelake-sm86' \
  '--build-dir=/opt/build/llamacpp/b10075-icelake-sm86' \
  '--install-dir=/opt/llama.cpp/b10075-icelake-sm86'; do
  require_contains "setup/cli/llm/llamacpp.sh" "${marker}"
done

for marker in \
  'Reviewed source-build example:' \
  'Model-free validation example:' \
  '--source-dir=/opt/src/ktransformers/v0.6.3-icelake-sm86-source' \
  '--build-dir=/opt/build/ktransformers/v0.6.3-icelake-sm86-source' \
  '--install-dir=/opt/venvs/ktransformers-v0.6.3-icelake-sm86-source'; do
  require_contains "setup/cli/llm/ktransformers.sh" "${marker}"
done

for document in \
  docs/cli/llm/llamacpp/readme.md \
  docs/cli/llm/ktransformers/readme.md; do
  require_contains "${document}" '## Flag interaction notes'
  require_contains "${document}" 'GitHub Actions'
  require_contains "${document}" 'remote'
done

for playbook in ansible/cli/llm/llamacpp.yml ansible/cli/llm/ktransformers.yml; do
  reject_contains "${playbook}" 'ansible.builtin.git:'
  reject_contains "${playbook}" 'ansible.builtin.get_url:'
  reject_contains "${playbook}" 'huggingface'
  if ! validate_yaml_file "${ROOT}/${playbook}"; then
    rc=1
  fi
  if ! validate_shell_payloads "${ROOT}/${playbook}"; then
    rc=1
  fi
done

for marker in \
  'llamacpp_facts_path: /etc/ansible/debian/facts/llamacpp.yml' \
  'llamacpp_staged_source_path' \
  'repository_url:' \
  'commit:' \
  'model_downloaded: false' \
  'persistent_server_started: false'; do
  require_contains "ansible/cli/llm/llamacpp.yml" "${marker}"
done

for marker in \
  'ktransformers_facts_path: /etc/ansible/debian/facts/ktransformers.yml' \
  'ktransformers_staged_source_path' \
  'sglang_repository_url:' \
  'sglang_commit:' \
  'llamacpp_required: false' \
  'model_downloaded: false' \
  'model_loaded: false' \
  'ktransformers_worktree_dir' \
  'python_source_sha256:' \
  'host_memory_semantics:'; do
  require_contains "ansible/cli/llm/ktransformers.yml" "${marker}"
done

llama_matrix="${ROOT}/ansible/files/llm/llamacpp/compatibility-matrix.yml"
kt_matrix="${ROOT}/ansible/files/llm/ktransformers/compatibility-matrix.yml"
profile_helper="${ROOT}/ansible/files/llm/source-profile.py"

python3 "${profile_helper}" \
  --matrix "${llama_matrix}" \
  --feature llamacpp \
  --profile b10075-icelake-sm86 \
  --repository-url https://github.com/ggml-org/llama.cpp.git \
  --release b10075 \
  --commit 76f46ad29d61fd8c1401e8221842934bf62a6064 >/dev/null || rc=1

python3 "${profile_helper}" \
  --matrix "${kt_matrix}" \
  --feature ktransformers \
  --profile v0.6.3-icelake-sm86-source \
  --repository-url https://github.com/kvcache-ai/ktransformers.git \
  --release v0.6.3 \
  --commit ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
  --sglang-repository-url https://github.com/kvcache-ai/sglang.git \
  --sglang-commit 8b636f9008dbad58c0a8e481b03e794739e6c146 >/dev/null || rc=1

if python3 "${profile_helper}" \
  --matrix "${llama_matrix}" \
  --feature llamacpp \
  --profile b10075-icelake-sm86 \
  --repository-url https://example.com/ggml-org/llama.cpp.git \
  --release b10075 \
  --commit 76f46ad29d61fd8c1401e8221842934bf62a6064 >/dev/null 2>&1; then
  contract.error "a changed repository URL with a reviewed commit was accepted"
fi

if python3 "${profile_helper}" \
  --matrix "${kt_matrix}" \
  --feature ktransformers \
  --profile v0.6.3-icelake-sm86-source \
  --repository-url https://github.com/kvcache-ai/ktransformers.git \
  --release v0.6.3 \
  --commit ce7c3dd \
  --sglang-repository-url https://github.com/kvcache-ai/sglang.git \
  --sglang-commit 8b636f9008dbad58c0a8e481b03e794739e6c146 >/dev/null 2>&1; then
  contract.error "a shortened KTransformers commit was accepted"
fi

for unsafe_repository_url in \
  'https://user@github.com/ggml-org/llama.cpp.git' \
  'https://github.com/ggml-org/llama.cpp.git?ref=b10075' \
  'https://github.com/ggml-org/llama.cpp.git#b10075'; do
  if python3 "${profile_helper}" \
    --matrix "${llama_matrix}" \
    --feature llamacpp \
    --profile b10075-icelake-sm86 \
    --repository-url "${unsafe_repository_url}" \
    --release b10075 \
    --commit 76f46ad29d61fd8c1401e8221842934bf62a6064 >/dev/null 2>&1; then
    contract.error "an unsafe repository URL was accepted: ${unsafe_repository_url}"
  fi
done

resolve_remote_tag() {
  local repository="$1" release="$2" output="" direct="" peeled=""
  output="$(git ls-remote --tags "${repository}" "refs/tags/${release}" "refs/tags/${release}^{}")"
  direct="$(printf '%s\n' "${output}" | awk -v ref="refs/tags/${release}" '$2 == ref {print $1}')"
  peeled="$(printf '%s\n' "${output}" | awk -v ref="refs/tags/${release}^{}" '$2 == ref {print $1}')"
  printf '%s\n' "${peeled:-${direct}}"
}

if [[ "${NETWORK_VERIFY}" == 1 ]]; then
  echo "[${ACTION_LABEL}] GitHub Actions network verification enabled"
  llama_remote_commit="$(
    resolve_remote_tag \
      https://github.com/ggml-org/llama.cpp.git \
      b10075
  )"
  [[ "${llama_remote_commit}" == 76f46ad29d61fd8c1401e8221842934bf62a6064 ]] ||
    contract.error "llama.cpp b10075 remote tag changed: ${llama_remote_commit}"

  kt_remote_commit="$(
    resolve_remote_tag \
      https://github.com/kvcache-ai/ktransformers.git \
      v0.6.3
  )"
  [[ "${kt_remote_commit}" == ce7c3ddbe93f7ac1f992375eed54058bbc512646 ]] ||
    contract.error "KTransformers v0.6.3 remote tag changed: ${kt_remote_commit}"

  git init -q "${TEST_ROOT}/ktransformers"
  git -C "${TEST_ROOT}/ktransformers" remote add origin https://github.com/kvcache-ai/ktransformers.git
  git -C "${TEST_ROOT}/ktransformers" fetch -q --depth=1 origin \
    refs/tags/v0.6.3:refs/tags/v0.6.3
  actual_sglang_commit="$(
    git -C "${TEST_ROOT}/ktransformers" \
      ls-tree ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
      third_party/sglang \
      | awk '{print $3}'
  )"
  [[ "${actual_sglang_commit}" == 8b636f9008dbad58c0a8e481b03e794739e6c146 ]] ||
    contract.error "KTransformers release SGLang submodule changed: ${actual_sglang_commit}"

  python_archive="${TEST_ROOT}/Python-3.12.3.tar.xz"
  curl -fsSL \
    https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tar.xz \
    -o "${python_archive}"
  actual_python_sha="$(sha256sum "${python_archive}" | awk '{print $1}')"
  expected_python_sha="$(
    python3 - "${kt_matrix}" <<'PY'
import json
import pathlib
import sys

matrix = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(matrix["profiles"][0]["python_source_sha256"])
PY
  )"
  [[ "${actual_python_sha}" == "${expected_python_sha}" ]] ||
    contract.error "Python 3.12.3 source SHA-256 changed: ${actual_python_sha}"
else
  echo "[${ACTION_LABEL}] network verification deferred to GitHub Actions"
fi

exit "${rc}"
