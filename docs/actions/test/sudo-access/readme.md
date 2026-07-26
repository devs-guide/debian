---
title: Sudo access policy test
section: Actions / Test sudo access
source_path: actions/test.sudo-access.sh
---

# Sudo access policy test

Exercises the GPU, NVIDIA, NVLink, and LLM-host delegated-root contract using
shell mocks.

```bash
bash actions/test.sudo-access.sh
```

The suite verifies:

- an already-root process never calls sudo;
- cached or passwordless sudo uses only noninteractive `sudo -n`;
- an interactive streamed runner authenticates exactly once with `sudo -v`
  through `/dev/tty`;
- cancelled authentication stops before package or Ansible activity;
- no-TTY execution without cached/passwordless credentials fails closed;
- both `wget | bash` and the `wget | sudo bash` compatibility form reach the
  managed command;
- preflight remains unprivileged;
- delegated root receives only the explicit environment allowlist and original
  argument boundaries; and
- no delegated sudo command downloads content or invokes a feature runner
  again.

The test also verifies that `apply` is a positional mode token after the
`bash -s --` separator. It does not invoke real sudo, download content,
install software, run Ansible, or access GPU hardware.

This action has no supported flags. Its purpose is runner-policy regression
testing, not validation of sudo credentials on the current machine.
