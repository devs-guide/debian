---
title: Node LTS runner
section: CLI / Node
source_path: setup/cli/node.sh
script_url: https://devs-guide.github.io/debian/setup/cli/node.sh
---

# Node LTS runner

Installs or updates the Node feature selected by `DEBIAN_NODE_*` variables.
Modes are `preflight`, `apply`, and `upgrade`; the default is `apply`.

## Preflight

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/node.sh | \
  env DEBIAN_NODE_MODE=preflight bash
```

## Shared Node LTS installation

This example installs the current Node LTS selection into the shared NVM
location and exposes `node`/`npm` through system symlinks.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/node.sh | \
  env DEBIAN_NODE_MODE=apply \
      DEBIAN_NODE_VERSION='lts/*' \
      DEBIAN_NODE_INSTALL_SCOPE=shared \
      DEBIAN_NODE_NPM_POLICY=bundled \
      DEBIAN_NODE_CREATE_SYSTEM_SYMLINKS=1 \
      DEBIAN_NODE_ENABLE_COREPACK=1 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_NODE_MODE` | Selects `preflight`, `apply`, or `upgrade`. |
| `DEBIAN_NODE_VERSION` | NVM version selector; `lts/*` follows the current LTS line. Pin a concrete version for repeatable hosts. |
| `DEBIAN_NODE_INSTALL_SCOPE` | `shared` installs under `/usr/local/lib/nvm`; `private` uses a per-user NVM directory. |
| `DEBIAN_NODE_NPM_POLICY` | Keeps the Node-bundled npm policy in this example. |
| `DEBIAN_NODE_CREATE_SYSTEM_SYMLINKS` | Makes the selected shared `node` and `npm` available on the normal system path. |
| `DEBIAN_NODE_ENABLE_COREPACK` | Enables Corepack for package-manager shims when the selected Node release supports it. |

The runner stages `ansible/cli/node.yml` and its runtime support before
invoking Ansible. Use `upgrade` with the same policy when intentionally moving
an existing host forward.
