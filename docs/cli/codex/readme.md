---
title: Codex CLI runner
section: CLI / Codex
source_path: setup/cli/codex.sh
script_url: https://devs-guide.github.io/debian/setup/cli/codex.sh
---

# Codex CLI runner

Sets up the project’s Node plus Codex CLI feature. It supports `preflight` and
`apply` modes and is independent of the baseline bootstrap playlist.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/codex.sh | bash
```

Review the runner’s `DEBIAN_CLI_CODEX_*` variables for version and install
scope controls before an apply run.
