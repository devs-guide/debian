---
title: Setup runners
section: Setup
source_path: setup
description: Baseline and host-level Debian setup entrypoints.
---

# Setup runners

These entrypoints establish the baseline host or provide shared support to
opt-in features. Published executable URLs always end in `.sh`.

## Start with the baseline

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

Choose an opt-in runner below only after reviewing its full policy example;
the baseline does not implicitly install every feature.

- [Bootstrap](/debian/setup/bootstrap/) — baseline Ansible bootstrap.
- [Debian compatibility entrypoint](/debian/setup/debian/) — compatibility
  alias for the baseline bootstrap flow.
- [Metal compatibility entrypoint](/debian/setup/metal/) — compatibility alias
  for the baseline bootstrap flow.
- [Hardware](/debian/setup/hardware/) — opt-in source-neutral host baseline.
- [Autologin](/debian/setup/autologin/) — console autologin only.
- [Release helper](/debian/setup/release-common/) — shared runner support.
- [Shared setup runner](/debian/setup/runner-common/) — delegated-root and
  dependency-manifest scaffolding, including the legacy migration inventory.
- [Essential packages](/debian/setup/essential-packages/) — manual baseline
  reference, not an automation entrypoint.
- [Prerequisites](/debian/setup/prerequisites/) — manual first-host reference.
