---
title: Shared runner contract test
section: Actions / Test runner contract
source_path: actions/test.runner-contract.sh
description: Focused static and mocked validation of delegated root execution and dependency staging.
---

# Shared runner contract test

Run the complete shared-runner contract:

```bash
bash actions/test.runner-contract.sh
```

It checks the shared privilege/staging API, NVIDIA and NVLink integration,
clean root environment, single bootstrap fetch, and documented legacy-runner
inventory. It then executes the shell-only staging and sudo mock suites.

The action does not call real sudo, access the network, install software, or
run Ansible.
