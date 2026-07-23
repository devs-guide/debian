---
title: Sudo access policy test
section: Actions / Test sudo access
source_path: actions/test.sudo-access.sh
---

# Sudo access policy test

Exercises the NVIDIA and NVLink strict sudo contract using shell mocks.

```bash
bash actions/test.sudo-access.sh
```

It verifies root, local cached-sudo, missing-TTY, and unprivileged streamed
managed-mode cases. It does not invoke real sudo, download content, install
software, run Ansible, or access GPU hardware.

This action has no supported flags. Its purpose is runner-policy regression
testing, not validation of sudo credentials on the current machine.
