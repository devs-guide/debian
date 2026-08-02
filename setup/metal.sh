#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/metal.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_ENTRY="${SCRIPT_DIR}/bootstrap.sh"
REMOTE_ENTRY="https://devs-guide.github.io/debian/setup/bootstrap.sh"

if [[ -r "${LOCAL_ENTRY}" ]]; then
  exec bash "${LOCAL_ENTRY}" "$@"
fi

wget -qO- "${REMOTE_ENTRY}" | bash -s -- "$@"
