# devs-guide/debian

Published Debian bootstrap and host-configuration project.

The repo now treats `ansible/` as the active runtime namespace.
Older Proxmox-specific runners, release lanes, and feature trees have been
removed or replaced.

## Bootstrap

Primary entrypoint:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

Compatibility aliases:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/debian.sh | bash
```

```bash
wget -qO- https://devs-guide.github.io/debian/setup/metal.sh | bash
```

## Optional Setup Runner

Codex CLI installer:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/codex.sh | bash
```

Hardware baseline runner:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/hardware | bash
```

Hardware preflight mode:

```bash
DEBIAN_HARDWARE_MODE=preflight wget -qO- https://devs-guide.github.io/debian/setup/hardware | bash
```

## Layout

- `setup/`: Debian entrypoints, shared bootstrap helper, and operator runners
- `ansible/`: baseline Debian playbooks and catalogs
- `ansible/group_vars/`: shared Debian defaults and release overlays
- `setup/`: operator-facing Debian setup runners
- `actions/`: GitHub Pages publish and validation scripts
- `prompt/`: local planning, workflow, release, and agent guidance
