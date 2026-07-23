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
