---
title: Debian setup documentation
section: Home
source_path: readme.md
description: Operator documentation for the published Debian setup runners.
---

# Debian setup documentation

This site documents the published Debian setup runners and the Ansible content
they stage. The documentation URL and the automation URL are deliberately
different: documentation uses extensionless paths, while all executable
published runners end in `.sh`.

## Start here

The baseline bootstrap entrypoint is:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

This is the complete default baseline command: it has no required feature
flags. On a local checkout, use `bash setup/bootstrap.sh` instead. Optional
hardware, CLI, GPU, and kiosk configuration is deliberately separate; follow
the linked feature page and copy its explicit policy command rather than
assuming bootstrap installs it.

The compatibility entrypoints are `/setup/debian.sh` and `/setup/metal.sh`.
They remain source files, not documentation routes.

## Documentation sections

- [Setup runners](/debian/setup/) covers bootstrap, host baseline, autologin,
  and the shared release helper.
- [CLI runners](/debian/cli/) covers opt-in developer, kiosk, NVIDIA, and
  NVLink features.
- [Ansible](/debian/ansible/) explains the package and user policy sources.
- [Actions](/debian/actions/) explains publication and validation tooling.
- [Kiosk](/debian/kiosk/) groups the supported kiosk workflow and retained
  reference material.

## Safety model

Read a feature page before using its runner. `preflight` or `validate` is
preferred when a runner offers it. NVIDIA and NVLink streamed `apply` runs
must be explicitly elevated by placing `sudo` on the right side of the pipe;
this avoids an implicit privileged re-download.
