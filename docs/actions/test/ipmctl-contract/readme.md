---
title: ipmctl contract action
section: Actions / Test / ipmctl
source_path: actions/test.ipmctl-contract.sh
---

# ipmctl contract action

`actions/test.ipmctl-contract.sh` performs repository-local validation of the
Debian 13 ipmctl feature. It checks:

- the two-mode `install` and `verify` runner interface;
- exact ipmctl and EDK2 tags, commits, and expected binary version;
- all three vendored patch SHA-256 values and sole target declarations;
- strict preimage, apply, reverse-check, postimage, and diff-check tasks;
- unmanaged-install refusal, managed receipt, and idempotence gates;
- read-only verification and LLM live-ipmctl integration;
- removal of the old source-profile, inventory, goal, and hosted-build paths;
- Bash syntax, YAML parsing, embedded shell syntax, and Ansible syntax when
  the validation environment provides Ansible.

```bash
bash actions/test.ipmctl-contract.sh
```

For a minimal local check without Ansible syntax validation:

```bash
bash actions/test.ipmctl-contract.sh --shell-only
```

The action does not clone source, compile ipmctl, install packages, run PMem
discovery, or change PMem state. Exact-source compilation and the four
read-only hardware probes are acceptance steps on the Debian 13 PMem host.
