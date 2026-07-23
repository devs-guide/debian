---
title: User policy
section: Ansible / Users
source_path: ansible/users.yml
---

# User policy

Managed user definitions come from `user_defs` in
`ansible/group_vars/all.yml`; `ansible/users.yml` applies them.

Review that source before running a baseline bootstrap on a real host. Account
membership, password-update behavior, and SSH access controls are host
security decisions and should be changed deliberately through versioned
configuration.

## Review before applying

```bash
sed -n '/^user_defs:/,/^[^[:space:]]/p' ansible/group_vars/all.yml
ansible-playbook ansible/users.yml --check
```

`--check` is an Ansible dry-run, not a replacement for reviewing the actual
managed accounts. Supply the correct inventory and become policy for the host;
the bootstrap runner does that as part of its complete baseline flow.
