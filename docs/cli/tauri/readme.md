---
title: Tauri runner
section: CLI / Tauri
source_path: setup/cli/tauri.sh
script_url: https://devs-guide.github.io/debian/setup/cli/tauri.sh
---

# Tauri runner

Sets up optional Tauri runtime or build dependencies. Modes are `preflight`,
`apply`, and `upgrade`.

## Build-host toolchain

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri.sh | \
  env DEBIAN_CLI_TAURI_MODE=apply \
      DEBIAN_CLI_TAURI_PROFILE=build \
      DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 \
      DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 \
      DEBIAN_CLI_TAURI_INSTALL_NODE=1 \
      DEBIAN_CLI_TAURI_NODE_INSTALL_SCOPE=shared \
      DEBIAN_CLI_TAURI_NODE_VERSION='lts/*' \
      DEBIAN_CLI_TAURI_ENABLE_COREPACK=1 \
      DEBIAN_CLI_TAURI_INSTALL_RUST=1 \
      DEBIAN_CLI_TAURI_RUST_TOOLCHAIN=stable \
      DEBIAN_CLI_TAURI_RUST_USER=root \
      DEBIAN_CLI_TAURI_INSTALL_CLI=1 \
      DEBIAN_CLI_TAURI_CLI_METHOD=npm \
      DEBIAN_CLI_TAURI_NPM_PACKAGE='@tauri-apps/cli' \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_CLI_TAURI_PROFILE` | Selects the runtime or build dependency profile. |
| `DEBIAN_CLI_TAURI_INSTALL_RUNTIME` / `DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS` | Explicitly enables runtime and native build dependencies. |
| `DEBIAN_CLI_TAURI_INSTALL_NODE` / `DEBIAN_CLI_TAURI_NODE_*` | Installs the selected Node policy for the Tauri CLI. |
| `DEBIAN_CLI_TAURI_INSTALL_RUST` / `DEBIAN_CLI_TAURI_RUST_*` | Installs Rust for the selected account and toolchain. |
| `DEBIAN_CLI_TAURI_INSTALL_CLI` / `DEBIAN_CLI_TAURI_CLI_METHOD` | Installs the Tauri CLI with the selected package-manager method. |
| `DEBIAN_CLI_TAURI_INSTALL_APPIMAGE_TOOLS` / `DEBIAN_CLI_TAURI_INSTALL_TEST_TOOLS` | Optional packaging and test tooling; omitted from this minimal build-host example. |

When setting variables for a streamed runner, put `env` on the **right** side
of the pipe (or export them first), so the downloaded shell receives the
`DEBIAN_CLI_TAURI_*` values. Use `preflight` before an apply run and `upgrade`
with the same policy when intentionally updating the toolchain.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri.sh | \
  env DEBIAN_CLI_TAURI_PROFILE=build bash
```
