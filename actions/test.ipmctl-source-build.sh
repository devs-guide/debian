#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.ipmctl-source-build"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "${TEST_PARENT%/}/test.ipmctl-source-build.XXXXXX")"

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && "${TEST_ROOT}" == "${TEST_PARENT%/}/test.ipmctl-source-build."* ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

echo "[${ACTION_LABEL}] building the reviewed Debian 13 Release source tuple..."

git init -q "${TEST_ROOT}/ipmctl"
git -C "${TEST_ROOT}/ipmctl" remote add origin https://github.com/intel/ipmctl.git
git -C "${TEST_ROOT}/ipmctl" fetch -q --depth=1 origin \
  refs/tags/v03.00.00.0538:refs/tags/v03.00.00.0538
git -C "${TEST_ROOT}/ipmctl" checkout -q --detach \
  a71f2fb1c90dd07f9862b71c789881132193e8f9

git init -q "${TEST_ROOT}/edk2"
git -C "${TEST_ROOT}/edk2" remote add origin https://github.com/tianocore/edk2.git
git -C "${TEST_ROOT}/edk2" fetch -q --depth=1 origin \
  refs/tags/edk2-stable202405:refs/tags/edk2-stable202405
git -C "${TEST_ROOT}/edk2" checkout -q --detach \
  3e722403cd16388a0e4044e705a2b34c841d76ca

(
  cd "${TEST_ROOT}/ipmctl"
  ./updateedk.sh
  cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${TEST_ROOT}/install"
  cmake --build build -j2
  cmake --install build
)

"${TEST_ROOT}/install/bin/ipmctl" version
ldd "${TEST_ROOT}/install/bin/ipmctl" | tee "${TEST_ROOT}/ldd.txt"
if grep -Fq 'not found' "${TEST_ROOT}/ldd.txt"; then
  echo "[${ACTION_LABEL}][error] installed binary has an unresolved library" >&2
  exit 1
fi
