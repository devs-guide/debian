#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION_LABEL="test.ipmctl-source-build"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "${TEST_PARENT%/}/test.ipmctl-source-build.XXXXXX")"
IPMCTL_RELEASE="v03.00.00.0538"
IPMCTL_COMMIT="a71f2fb1c90dd07f9862b71c789881132193e8f9"
IPMCTL_BINARY_VERSION="03.00.00.0538"
IPMCTL_OS_PATCH="src/os/patches/0001-Ignore-STATIC_ASSERTs-and-NULL-define-for-os-and-ut-builds.patch"
EDK2_RELEASE="edk2-stable202111"
EDK2_COMMIT="bb1bba3d776733c41dbfa2d1dc0fe234819a79f2"

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && "${TEST_ROOT}" == "${TEST_PARENT%/}/test.ipmctl-source-build."* ]]; then
    rm -rf -- "${TEST_ROOT}"
  fi
}
trap cleanup EXIT

echo "[${ACTION_LABEL}] building the reviewed Debian 13 Release source tuple..."

git init -q "${TEST_ROOT}/ipmctl"
git -C "${TEST_ROOT}/ipmctl" remote add origin https://github.com/intel/ipmctl.git
git -C "${TEST_ROOT}/ipmctl" fetch -q --depth=1 --no-tags origin \
  "refs/tags/${IPMCTL_RELEASE}:refs/tags/${IPMCTL_RELEASE}"
if [[ "$(git -C "${TEST_ROOT}/ipmctl" rev-list -n 1 "refs/tags/${IPMCTL_RELEASE}")" != "${IPMCTL_COMMIT}" ]]; then
  echo "[${ACTION_LABEL}][error] reviewed ipmctl tag does not resolve to ${IPMCTL_COMMIT}" >&2
  exit 1
fi
git -C "${TEST_ROOT}/ipmctl" checkout -q --detach "${IPMCTL_COMMIT}"

git init -q "${TEST_ROOT}/edk2"
git -C "${TEST_ROOT}/edk2" remote add origin https://github.com/tianocore/edk2.git
git -C "${TEST_ROOT}/edk2" fetch -q --depth=1 --no-tags origin \
  "refs/tags/${EDK2_RELEASE}:refs/tags/${EDK2_RELEASE}"
if [[ "$(git -C "${TEST_ROOT}/edk2" rev-list -n 1 "refs/tags/${EDK2_RELEASE}")" != "${EDK2_COMMIT}" ]]; then
  echo "[${ACTION_LABEL}][error] reviewed edk2 tag does not resolve to ${EDK2_COMMIT}" >&2
  exit 1
fi
git -C "${TEST_ROOT}/edk2" checkout -q --detach "${EDK2_COMMIT}"

(
  cd "${TEST_ROOT}/ipmctl"
  ./updateedk.sh
  if [[ ! -x ./patch_OS.sh || ! -f "${IPMCTL_OS_PATCH}" ]]; then
    echo "[${ACTION_LABEL}][error] pinned upstream Linux patch procedure is incomplete" >&2
    exit 1
  fi
  patch_targets="$(
    git apply --numstat "${IPMCTL_OS_PATCH}" |
      awk -F '\t' '{print $3}' |
      sort -u
  )"
  if [[ "${patch_targets}" != "MdePkg/Include/Base.h" ]]; then
    echo "[${ACTION_LABEL}][error] upstream OS patch targets changed: ${patch_targets}" >&2
    exit 1
  fi
  if ! git apply --check \
    --ignore-space-change \
    --ignore-whitespace \
    --whitespace=nowarn \
    "${IPMCTL_OS_PATCH}"; then
    echo "[${ACTION_LABEL}][error] upstream OS patch cannot be applied to the reviewed EDK2 source" >&2
    exit 1
  fi
  ./patch_OS.sh | tee "${TEST_ROOT}/patch-os.txt"
  if ! git apply --reverse --check "${IPMCTL_OS_PATCH}"; then
    echo "[${ACTION_LABEL}][error] upstream OS patch was not applied cleanly" >&2
    exit 1
  fi
  cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILDNUM="${IPMCTL_BINARY_VERSION}" \
    -DCMAKE_INSTALL_PREFIX="${TEST_ROOT}/install"
  if ! grep -R -Fq -- '-Werror' build/CMakeFiles; then
    echo "[${ACTION_LABEL}][error] reviewed Release configuration no longer enables -Werror" >&2
    exit 1
  fi
  cmake --build build -j2
  cmake --install build
)

version_output="$("${TEST_ROOT}/install/bin/ipmctl" version)"
printf '%s\n' "${version_output}"
version_token="$(
  printf '%s\n' "${version_output}" |
    grep -Eo '[0-9]{2}[.][0-9]{2}[.][0-9]{2}[.][0-9]{4}' |
    head -n 1 ||
    true
)"
if [[ "${version_token}" != "${IPMCTL_BINARY_VERSION}" ]]; then
  echo "[${ACTION_LABEL}][error] installed binary reports ${version_token:-no version}, expected ${IPMCTL_BINARY_VERSION}" >&2
  exit 1
fi
ldd "${TEST_ROOT}/install/bin/ipmctl" | tee "${TEST_ROOT}/ldd.txt"
if grep -Fq 'not found' "${TEST_ROOT}/ldd.txt"; then
  echo "[${ACTION_LABEL}][error] installed binary has an unresolved library" >&2
  exit 1
fi
