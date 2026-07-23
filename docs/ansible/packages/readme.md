---
title: Package catalog
section: Ansible / Packages
source_path: ansible/packages.yml
---

# Package catalog

`ansible/install.packages.yml` consumes package groups defined in
`ansible/packages.yml`.

Default groups cover the project’s baseline categories such as base packages,
time sync, security, storage, networking, hardware information, developer
tools, and power policy. Optional desktop, Apple media, GPU-vendor, and
firmware groups remain disabled unless explicitly selected.

Example package-group override:

```sh
ansible-playbook ansible/install.packages.yml \
  -e '{"package_group_overrides":{"desktop_rdp_optional":true}}'
```
