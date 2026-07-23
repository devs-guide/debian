# `actions/test.sudo-access.sh`

Tests the strict sudo policy shared by the Phase 1 NVIDIA and NVLink runners.
It uses shell mocks rather than real privilege escalation.

```bash
bash actions/test.sudo-access.sh
```

For each runner, it verifies that:

- an already-root process does not call sudo;
- a local script with cached sudo re-execs the same path and preserves flags;
- a local script without a usable controlling terminal fails immediately; and
- an unprivileged streamed managed runner fails without invoking sudo or a
  network self-re-download.

It does not install software, contact the network, invoke real sudo, run
Ansible, or access GPU hardware.
