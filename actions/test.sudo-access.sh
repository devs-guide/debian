#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

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

run_case() {
  local runner="$1" case_name="$2" result="" status_code=0
  shift 2
  set +e
  result="$(TEST_RUNNER="${ROOT}/${runner}" bash -c "$*" 2>&1)"
  status_code=$?
  set -e
  printf '[test.sudo-access] %s %s\n' "${runner}" "${case_name}"
  printf '%s\n' "${result}"
  CASE_OUTPUT="${result}"
  CASE_STATUS="${status_code}"
}

for runner in setup/cli/nvidia.sh setup/cli/nvlink.sh; do
  run_case "${runner}" root '
    source "${TEST_RUNNER}"
    runner.euid() { printf 0; }
    sudo() { printf "unexpected sudo\n"; return 99; }
    ensure.root.or.sudo.reexec apply --gpu=all
  '
  expect_status 0 "${CASE_STATUS}" "${runner} root"
  [[ "${CASE_OUTPUT}" != *"unexpected sudo"* ]] || fail "${runner} root: called sudo"

  run_case "${runner}" local-cached-sudo '
    source "${TEST_RUNNER}"
    runner.euid() { printf 1000; }
    FEATURE_MODE=apply
    current.script.path() { printf "/safe/local/runner.sh\n"; }
    sudo() {
      [[ "$1" == -n && "$2" == true ]] && return 0
      printf "unexpected sudo invocation: %s\n" "$*"
      return 99
    }
    exec() {
      printf "EXEC"
      local argument
      for argument in "$@"; do printf " <%q>" "${argument}"; done
      printf "\n"
    }
    ensure.root.or.sudo.reexec apply "--label=two words" --gpu=all
  '
  expect_status 0 "${CASE_STATUS}" "${runner} local cached sudo"
  expect_contains 'EXEC <sudo> <env>' "${CASE_OUTPUT}" "${runner} local cached sudo"
  expect_contains '<bash> </safe/local/runner.sh> <apply> <--label=two\ words> <--gpu=all>' "${CASE_OUTPUT}" "${runner} argument preservation"
  [[ "${CASE_OUTPUT}" != *"wget"* && "${CASE_OUTPUT}" != *"curl"* ]] || fail "${runner} local cached sudo: attempted network re-entry"

  run_case "${runner}" local-no-tty '
    source "${TEST_RUNNER}"
    runner.euid() { printf 1000; }
    FEATURE_MODE=apply
    current.script.path() { printf "/safe/local/runner.sh\n"; }
    have.controlling.tty() { return 1; }
    sudo() {
      [[ "$1" == -n && "$2" == true ]] && return 1
      printf "unexpected sudo invocation: %s\n" "$*"
      return 99
    }
    exec() { printf "unexpected exec\n"; }
    ensure.root.or.sudo.reexec apply
  '
  expect_status 1 "${CASE_STATUS}" "${runner} local no tty"
  expect_contains 'no usable /dev/tty is available' "${CASE_OUTPUT}" "${runner} local no tty"
  [[ "${CASE_OUTPUT}" != *"unexpected exec"* ]] || fail "${runner} local no tty: re-executed unexpectedly"

  run_case "${runner}" streamed-unprivileged '
    source "${TEST_RUNNER}"
    runner.euid() { printf 1000; }
    FEATURE_MODE=apply
    current.script.path() { return 1; }
    sudo() { printf "unexpected sudo\n"; return 99; }
    ensure.root.or.sudo.reexec apply
  '
  expect_status 3 "${CASE_STATUS}" "${runner} streamed unprivileged"
  expect_contains 'runner was executed from stdin' "${CASE_OUTPUT}" "${runner} streamed unprivileged"
  [[ "${CASE_OUTPUT}" != *"unexpected sudo"* ]] || fail "${runner} streamed unprivileged: called sudo"
done

exit "${rc}"
