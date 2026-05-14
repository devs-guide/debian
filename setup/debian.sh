#!/usr/bin/env bash
# Published path: https://devs-guide.github.io/debian/setup/debian.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/bootstrap.sh" "$@"
