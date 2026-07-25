#!/usr/bin/env bash
# Shared validation helpers for focused actions and validate.runtime.sh.

if [[ -z "${ROOT:-}" ]]; then
  printf '[actions.contracts][error] ROOT must be set before sourcing actions/lib/contracts.sh\n' >&2
  return 1 2>/dev/null || exit 1
fi

: "${ACTION_LABEL:=actions.contracts}"
: "${rc:=0}"

contract.error() {
  printf '[%s][error] %s\n' "${ACTION_LABEL}" "$*" >&2
  rc=1
}

contract.warn() {
  printf '[%s][warn] %s\n' "${ACTION_LABEL}" "$*" >&2
}

contract.path() {
  local path="${1:-}"
  if [[ "${path}" == /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${ROOT}" "${path}"
  fi
}

search_regex() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -n -- "${pattern}" "$@"
    return
  fi

  grep -R -nE -- "${pattern}" "$@"
}

require_file() {
  local file="$1"
  local path=""
  path="$(contract.path "${file}")"
  if [[ ! -f "${path}" ]]; then
    contract.error "missing required file: ${file}"
  fi
}

require_contains() {
  local file="$1"
  local pattern="$2"
  local path=""
  path="$(contract.path "${file}")"
  if ! grep -Fq -- "${pattern}" "${path}"; then
    contract.error "missing pattern in ${file}: ${pattern}"
  fi
}

reject_contains() {
  local file="$1"
  local pattern="$2"
  local path=""
  path="$(contract.path "${file}")"
  if grep -Fq -- "${pattern}" "${path}"; then
    contract.error "unexpected pattern in ${file}: ${pattern}"
  fi
}

require_regex() {
  local file="$1"
  local pattern="$2"
  local path=""
  path="$(contract.path "${file}")"
  if ! grep -Eq -- "${pattern}" "${path}"; then
    contract.error "missing regular-expression contract in ${file}: ${pattern}"
  fi
}

reject_regex() {
  local file="$1"
  local pattern="$2"
  local path=""
  path="$(contract.path "${file}")"
  if grep -Eq -- "${pattern}" "${path}"; then
    contract.error "unexpected regular-expression match in ${file}: ${pattern}"
  fi
}

require_shell_syntax() {
  local file="$1"
  local path=""
  path="$(contract.path "${file}")"
  if ! bash -n "${path}"; then
    contract.error "${file} must pass bash -n"
  fi
}

run_contract_action() {
  local action="$1"
  local path=""
  path="$(contract.path "${action}")"
  if ! bash "${path}"; then
    contract.error "${action} failed"
  fi
}

validate_yaml_file() {
  local file="$1"
  local label="${ACTION_LABEL}"

  if python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 - "${file}" "${label}" <<'PY'
from pathlib import Path
import sys
import yaml

path = Path(sys.argv[1])
label = sys.argv[2]
try:
    yaml.safe_load(path.read_text())
except Exception as exc:
    print(f"[{label}][error] invalid YAML: {path}: {exc}")
    raise SystemExit(1)
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ACTION_VALIDATION_LABEL="${label}" ruby - "${file}" <<'RUBY'
require "yaml"

path = ARGV.fetch(0)
label = ENV.fetch("ACTION_VALIDATION_LABEL", "actions.contracts")
begin
  YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
rescue => e
  warn "[#{label}][error] invalid YAML: #{path}: #{e}"
  exit 1
end
RUBY
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    contract.warn "YAML parser unavailable; running heredoc indentation regression check: ${file}"
    python3 - "${file}" "${label}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
label = sys.argv[2]
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
                    f"[{label}][error] malformed heredoc terminator indentation in {path}: line {j + 1}"
                )
                raise SystemExit(1)
            found_terminator = True
            break

        if stripped and candidate_indent < base_indent:
            print(
                f"[{label}][error] malformed heredoc body indentation in {path}: line {j + 1}"
            )
            raise SystemExit(1)
        j += 1

    if not found_terminator:
        print(f"[{label}][error] unterminated heredoc block in {path}: line {i + 1}")
        raise SystemExit(1)

    i = j + 1
PY
    return
  fi

  contract.error "no YAML parser is available for ${file}"
  return 1
}

validate_shell_payloads() {
  local file="$1"
  local label="${ACTION_LABEL}"

  if ! command -v python3 >/dev/null 2>&1; then
    contract.error "python3 is required to validate shell payloads in ${file}"
    return 1
  fi

  python3 - "${file}" "${label}" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

path = Path(sys.argv[1])
label = sys.argv[2]
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
        return None, f"[{label}][error] invalid YAML while extracting shell payloads: {path}: {exc}"

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
        match = re.match(r"^(\s*)(?:ansible\.builtin\.shell|shell):\s*\|\s*$", line)
        if not match:
            i += 1
            continue
        base_indent = len(match.group(1))
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

for index, raw_payload in enumerate(shell_blocks, start=1):
    payload = neutralize_jinja(raw_payload)
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as temporary:
        temporary.write(payload)
        temporary_path = temporary.name
    try:
        result = subprocess.run(
            ["bash", "-n", temporary_path],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            stderr = (result.stderr or "").strip()
            print(f"[{label}][error] shell payload parse failed: {path} block#{index}")
            if stderr:
                print(stderr)
            raise SystemExit(1)
    finally:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
PY
}
