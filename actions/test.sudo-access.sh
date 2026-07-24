#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_HELPER="${ROOT}/setup/runner.common.sh"
RELEASE_HELPER="${ROOT}/setup/release.common.sh"
TEST_TMP_PARENT="${TMPDIR:-/tmp}"
TEST_TMP="$(mktemp -d "${TEST_TMP_PARENT%/}/test.sudo-access.XXXXXX")"
TEST_TTY="${TEST_TMP}/tty"
rc=0
case_index=0
CASE_OUTPUT=""
CASE_STATUS=0
CASE_TRACE=""
ALL_SUDO_TRACE=""

: > "${TEST_TTY}"
chmod 0600 "${TEST_TTY}"

cleanup() {
  if [[ -n "${TEST_TMP:-}" && "${TEST_TMP}" == "${TEST_TMP_PARENT%/}/test.sudo-access."* ]]; then
    rm -rf -- "${TEST_TMP}"
  fi
}
trap cleanup EXIT

fail() {
  printf '[test.sudo-access][error] %s\n' "$*" >&2
  rc=1
}

expect_status() {
  local expected="$1" actual="$2" label="$3"
  [[ "${actual}" -eq "${expected}" ]] || fail "${label}: expected status ${expected}, got ${actual}"
}

expect_contains() {
  local needle="$1" haystack="$2" label="$3"
  [[ "${haystack}" == *"${needle}"* ]] || fail "${label}: missing ${needle}"
}

expect_not_contains() {
  local needle="$1" haystack="$2" label="$3"
  [[ "${haystack}" != *"${needle}"* ]] || fail "${label}: unexpectedly contained ${needle}"
}

expect_count() {
  local expected="$1" needle="$2" haystack="$3" label="$4"
  local actual=""
  actual="$(printf '%s\n' "${haystack}" | grep -F -c -- "${needle}" || true)"
  [[ "${actual}" -eq "${expected}" ]] || \
    fail "${label}: expected ${expected} occurrence(s) of ${needle}, got ${actual}"
}

run_case() {
  local label="$1"
  local runner="${2:-}"
  local script="$3"
  local trace=""
  local result=""
  local status_code=0

  case_index=$((case_index + 1))
  trace="${TEST_TMP}/case-${case_index}.trace"
  : > "${trace}"

  set +e
  result="$(
    /usr/bin/env -i \
      HOME="${HOME:-/tmp}" \
      PATH="/usr/local/bin:/usr/bin:/bin" \
      TEST_ROOT="${ROOT}" \
      TEST_HELPER="${RUNNER_HELPER}" \
      TEST_RELEASE="${RELEASE_HELPER}" \
      TEST_RUNNER="${runner}" \
      TEST_TRACE="${trace}" \
      TEST_TTY="${TEST_TTY}" \
      /bin/bash -c "${script}" 2>&1
  )"
  status_code=$?
  set -e

  CASE_OUTPUT="${result}"
  CASE_STATUS="${status_code}"
  CASE_TRACE="$(sed -n '1,240p' "${trace}")"
  ALL_SUDO_TRACE="${ALL_SUDO_TRACE}${CASE_TRACE}"$'\n'

  printf '[test.sudo-access] %s\n' "${label}"
  if [[ -n "${CASE_OUTPUT}" ]]; then
    printf '%s\n' "${CASE_OUTPUT}"
  fi
  if [[ -n "${CASE_TRACE}" ]]; then
    printf '%s\n' "${CASE_TRACE}"
  fi
}

# Shared helper: root is a no-sudo path.
run_case "shared helper: already root" "" '
    source "${TEST_HELPER}"
    runner.euid() { printf 0; }
    sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      printf " <%q>" "$@" >> "${TEST_TRACE}"
      printf "\n" >> "${TEST_TRACE}"
      return 99
    }
    root.command() { printf "ROOT_COMMAND <%q>\n" "$1"; }
    runner.ensure.privileged.session
    runner.run.as.root root.command "two words"
'
expect_status 0 "${CASE_STATUS}" "already-root helper"
expect_contains 'ROOT_COMMAND <two\ words>' "${CASE_OUTPUT}" "already-root argument preservation"
expect_count 0 'sudo' "${CASE_TRACE}" "already-root helper"

# Shared helper: cached or passwordless sudo remains noninteractive and preserves argv.
run_case "shared helper: cached sudo" "" '
    source "${TEST_HELPER}"
    runner.euid() { printf 1000; }
    trace.sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}" >> "${TEST_TRACE}"; done
      printf "\n" >> "${TEST_TRACE}"
    }
    sudo() {
      trace.sudo "$@"
      if [[ "${1:-}" == -n && "${2:-}" == -- && "${3:-}" == true ]]; then
        return 0
      fi
      if [[ "${1:-}" == -n && "${2:-}" == -- ]]; then
        return 0
      fi
      return 99
    }
    runner.ensure.privileged.session
    runner.run.as.root /mock/package "--label=two words" --gpu=all
    runner.run.as.root /mock/ansible
'
expect_status 0 "${CASE_STATUS}" "cached sudo helper"
expect_count 1 'sudo <-n> <--> <true>' "${CASE_TRACE}" "cached sudo authentication"
expect_contains 'sudo <-n> <--> </mock/package> <--label=two\ words> <--gpu=all>' "${CASE_TRACE}" "cached sudo argument preservation"
expect_contains 'sudo <-n> <--> </mock/ansible>' "${CASE_TRACE}" "cached sudo delegated command"
expect_count 0 'sudo <-v>' "${CASE_TRACE}" "cached sudo prompt"

# Shared helper: streamed interactive execution authenticates once through the TTY,
# then every delegated command uses the cached noninteractive credential.
run_case "shared helper: interactive streamed sudo" "" '
    RUNNER_TTY_PATH="${TEST_TTY}"
    source "${TEST_HELPER}"
    runner.euid() { printf 1000; }
    sudo_ready=0
    trace.sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}" >> "${TEST_TRACE}"; done
      printf "\n" >> "${TEST_TRACE}"
    }
    sudo() {
      trace.sudo "$@"
      if [[ "${1:-}" == -n && "${2:-}" == -- && "${3:-}" == true ]]; then
        [[ "${sudo_ready}" == 1 ]]
        return
      fi
      if [[ "${1:-}" == -v && "$#" -eq 1 ]]; then
        sudo_ready=1
        return 0
      fi
      if [[ "${1:-}" == -n && "${2:-}" == -- && "${sudo_ready}" == 1 ]]; then
        return 0
      fi
      return 99
    }
    runner.ensure.privileged.session
    runner.run.as.root /mock/package
    runner.run.as.root /mock/ansible
'
expect_status 0 "${CASE_STATUS}" "interactive streamed helper"
expect_count 1 'sudo <-v>' "${CASE_TRACE}" "interactive authentication count"
expect_contains 'sudo <-n> <--> </mock/package>' "${CASE_TRACE}" "interactive package delegation"
expect_contains 'sudo <-n> <--> </mock/ansible>' "${CASE_TRACE}" "interactive Ansible delegation"

# Shared helper: a noninteractive caller without cached credentials fails closed.
run_case "shared helper: no TTY and no cached sudo" "" '
    RUNNER_TTY_PATH="${TEST_TTY}.missing"
    source "${TEST_HELPER}"
    runner.euid() { printf 1000; }
    trace.sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}" >> "${TEST_TRACE}"; done
      printf "\n" >> "${TEST_TRACE}"
    }
    sudo() {
      trace.sudo "$@"
      return 1
    }
    runner.ensure.privileged.session
'
expect_status 1 "${CASE_STATUS}" "no-TTY helper"
expect_contains 'no usable /dev/tty is available' "${CASE_OUTPUT}" "no-TTY diagnostic"
expect_count 0 'sudo <-v>' "${CASE_TRACE}" "no-TTY prompt"

for runner in setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  runner_path="${ROOT}/${runner}"

  # A cancelled prompt must stop at the first managed-mode operation.
  run_case "${runner}: cancelled authentication" "${runner_path}" '
    source "${TEST_RUNNER}"
    RUNNER_TTY_PATH="${TEST_TTY}"
    source "${TEST_HELPER}"
    runner.euid() { printf 1000; }
    FEATURE_MODE=apply
    trace.sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}" >> "${TEST_TRACE}"; done
      printf "\n" >> "${TEST_TRACE}"
    }
    sudo() {
      trace.sudo "$@"
      if [[ "${1:-}" == -n ]]; then return 1; fi
      if [[ "${1:-}" == -v ]]; then return 1; fi
      return 99
    }
    source.release.common() { printf "ACTIVITY source-release\n" >> "${TEST_TRACE}"; }
    require.apt() { printf "ACTIVITY package\n" >> "${TEST_TRACE}"; }
    prepare.feature.files() { printf "ACTIVITY fetch\n" >> "${TEST_TRACE}"; }
    ensure.local.ansible.as.root() { printf "ACTIVITY bootstrap\n" >> "${TEST_TRACE}"; }
    run.feature.playbook() { printf "ACTIVITY ansible\n" >> "${TEST_TRACE}"; }
    run.managed.mode
  '
  expect_status 3 "${CASE_STATUS}" "${runner} cancelled authentication"
  expect_contains 'sudo authentication failed or was cancelled' "${CASE_OUTPUT}" "${runner} cancelled authentication diagnostic"
  expect_count 1 'sudo <-v>' "${CASE_TRACE}" "${runner} cancelled authentication count"
  expect_not_contains 'ACTIVITY' "${CASE_TRACE}" "${runner} cancellation ordering"

  # wget | bash enters managed mode as the invoking user and delegates root only.
  run_case "${runner}: wget pipe bash managed compatibility" "${runner_path}" '
    source "${TEST_RUNNER}"
    source "${TEST_HELPER}"
    runner.euid() { printf 1000; }
    sudo() {
      printf "sudo" >> "${TEST_TRACE}"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}" >> "${TEST_TRACE}"; done
      printf "\n" >> "${TEST_TRACE}"
      [[ "${1:-}" == -n && "${2:-}" == -- && "${3:-}" == true ]]
    }
    FEATURE_MODE=apply
    NVLINK_INSTALL_BUILD_TOOLS=0
    source.release.common() { :; }
    require.apt() { :; }
    require.debian() { :; }
    require.supported.platform() { :; }
    prepare.feature.files() { :; }
    ensure.local.ansible.as.root() { :; }
    write.nvidia.extra.vars.file() { :; }
    write.extra.vars.file() { :; }
    run.feature.playbook() { :; }
    run.managed.mode
    printf "MANAGED_OK\n"
  '
  expect_status 0 "${CASE_STATUS}" "${runner} wget pipe bash managed path"
  expect_contains 'MANAGED_OK' "${CASE_OUTPUT}" "${runner} wget pipe bash managed path"
  expect_count 1 'sudo <-n> <--> <true>' "${CASE_TRACE}" "${runner} managed authentication count"

  # wget | sudo bash starts as root and remains a supported compatibility form.
  run_case "${runner}: wget pipe sudo bash managed compatibility" "${runner_path}" '
    source "${TEST_RUNNER}"
    source "${TEST_HELPER}"
    runner.euid() { printf 0; }
    sudo() {
      printf "unexpected sudo\n" >> "${TEST_TRACE}"
      return 99
    }
    FEATURE_MODE=apply
    NVLINK_INSTALL_BUILD_TOOLS=0
    source.release.common() { :; }
    require.apt() { :; }
    require.debian() { :; }
    require.supported.platform() { :; }
    prepare.feature.files() { :; }
    ensure.local.ansible.as.root() { :; }
    write.nvidia.extra.vars.file() { :; }
    write.extra.vars.file() { :; }
    run.feature.playbook() { :; }
    run.managed.mode
    printf "MANAGED_OK\n"
  '
  expect_status 0 "${CASE_STATUS}" "${runner} wget pipe sudo bash managed path"
  expect_contains 'MANAGED_OK' "${CASE_OUTPUT}" "${runner} wget pipe sudo bash managed path"
  expect_not_contains 'unexpected sudo' "${CASE_TRACE}" "${runner} root-started compatibility"

  # The preflight branch never establishes a privileged session.
  run_case "${runner}: preflight is unprivileged" "${runner_path}" '
    source "${TEST_RUNNER}"
    sudo() {
      printf "unexpected sudo\n" >> "${TEST_TRACE}"
      return 99
    }
    source.runner.common() { :; }
    prepare.feature.files() { :; }
    run.read.only.preflight() { printf "PREFLIGHT_OK\n"; }
    main preflight
  '
  expect_status 0 "${CASE_STATUS}" "${runner} preflight"
  expect_contains 'PREFLIGHT_OK' "${CASE_OUTPUT}" "${runner} preflight"
  expect_not_contains 'unexpected sudo' "${CASE_TRACE}" "${runner} preflight"

  # The feature runner must construct an isolated root environment explicitly.
  run_case "${runner}: delegated environment allowlist" "${runner_path}" '
    source "${TEST_RUNNER}"
    source "${TEST_RELEASE}"
    runner.run.as.root() {
      printf "ROOT"
      local argument=""
      for argument in "$@"; do printf " <%q>" "${argument}"; done
      printf "\n"
    }
    COMMON_HELPER_PATH=/staged/release.common.sh
    UNSAFE_SECRET=must-not-cross-boundary
    export UNSAFE_SECRET
    ensure.local.ansible.as.root
  '
  expect_status 0 "${CASE_STATUS}" "${runner} environment allowlist"
  expect_contains 'ROOT </usr/bin/env> <-i>' "${CASE_OUTPUT}" "${runner} isolated root environment"
  expect_contains '<HOME=/root>' "${CASE_OUTPUT}" "${runner} root HOME allowlist"
  expect_contains '<PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin>' "${CASE_OUTPUT}" "${runner} root PATH allowlist"
  expect_not_contains 'UNSAFE_SECRET' "${CASE_OUTPUT}" "${runner} environment allowlist"
  expect_not_contains 'must-not-cross-boundary' "${CASE_OUTPUT}" "${runner} environment allowlist value"

  # `bash -s -- apply` passes "apply"; the accidental single token "--apply" is invalid.
  run_case "${runner}: apply mode token" "${runner_path}" '
    source "${TEST_RUNNER}"
    parse.arguments apply
    printf "MODE=%s\n" "${FEATURE_MODE}"
  '
  expect_status 0 "${CASE_STATUS}" "${runner} apply token"
  expect_contains 'MODE=apply' "${CASE_OUTPUT}" "${runner} apply token"

  run_case "${runner}: reject accidental --apply" "${runner_path}" '
    source "${TEST_RUNNER}"
    parse.arguments --apply
  '
  expect_status 64 "${CASE_STATUS}" "${runner} accidental --apply"
  expect_contains 'Unsupported option: --apply' "${CASE_OUTPUT}" "${runner} accidental --apply diagnostic"
done

expect_not_contains 'wget' "${ALL_SUDO_TRACE}" "delegated sudo command set"
expect_not_contains 'curl' "${ALL_SUDO_TRACE}" "delegated sudo command set"
expect_not_contains 'nvidia.sh' "${ALL_SUDO_TRACE}" "delegated sudo command set"
expect_not_contains 'nvlink.sh' "${ALL_SUDO_TRACE}" "delegated sudo command set"

exit "${rc}"
