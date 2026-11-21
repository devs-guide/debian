#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/debian.sh
# Published usage: wget -qO- https://devs-guide.github.io/debian/setup/debian.sh | bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_ENTRY="${SCRIPT_DIR}/bootstrap.sh"
REMOTE_ENTRY="https://devs-guide.github.io/debian/setup/bootstrap.sh"

if [[ -r "${LOCAL_ENTRY}" ]]; then
  exec bash "${LOCAL_ENTRY}" "$@"
fi

command -v wget >/dev/null 2>&1 || {
  printf '[setup.debian][error] wget is required to load the published bootstrap runner.\n' >&2
  exit 1
}
exec bash -c 'wget -qO- "$1" | bash -s -- "${@:2}"' bash "${REMOTE_ENTRY}" "$@"
