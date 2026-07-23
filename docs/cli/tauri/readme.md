---
title: Tauri runner
section: CLI / Tauri
source_path: setup/cli/tauri.sh
script_url: https://devs-guide.github.io/debian/setup/cli/tauri.sh
---

# Tauri runner

Sets up optional Tauri runtime or build dependencies. Modes are `preflight`,
`apply`, and `upgrade`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri.sh | bash
```

When setting variables for a streamed runner, put `env` on the **right** side
of the pipe (or export them first), so the downloaded shell receives the
`DEBIAN_CLI_TAURI_*` values.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri.sh | \
  env DEBIAN_CLI_TAURI_PROFILE=build bash
```
