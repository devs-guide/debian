---
title: Release common helper
section: Setup / Release helper
source_path: setup/release.common.sh
---

# Release common helper

`setup/release.common.sh` is shared implementation support for the setup
runners. It resolves Debian release policy, controller Python capability, and
runtime Ansible support files.

It is not a standalone operator entrypoint. Use a documented bootstrap or CLI
runner instead. Its public source URL is fetched by those runners as needed;
do not pipe this helper directly into a shell because it has no feature mode or
operator-facing policy contract.
