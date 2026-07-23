---
title: Ansible policy
section: Ansible
source_path: ansible
---

# Ansible policy

The published runners stage the Ansible content under `ansible/` at runtime.
The package catalog and user policy are documented here; feature-specific
playbooks remain documented by their matching runner pages.

- [Package catalog](/debian/ansible/packages/)
- [User policy](/debian/ansible/users/)

The baseline playlist is `ansible/install.playbooks.txt`. It intentionally
does not include opt-in CLI, NVIDIA, or NVLink validation playbooks.

## Local-checkout invocation

These playbooks are intended for a prepared local checkout or the runtime tree
staged by a runner. Do not fetch an Ansible YAML file alone and treat it as a
standalone shell script.

```bash
ansible-playbook ansible/install.packages.yml \
  -e '{"package_group_overrides":{"desktop_rdp_optional":false}}'
```

The exact inventory, privilege, and release-overlay choices are host policy.
For first-time hosts, use the [bootstrap runner](/debian/setup/bootstrap/),
which resolves and stages those inputs together.
