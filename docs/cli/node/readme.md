---
title: Node LTS runner
section: CLI / Node
source_path: setup/cli/node.sh
script_url: https://devs-guide.github.io/debian/setup/cli/node.sh
---

# Node LTS runner

Installs or updates the Node feature selected by `DEBIAN_NODE_*` variables.
Modes are `preflight`, `apply`, and `upgrade`; the default is `apply`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/node.sh | bash
```

For a read-only review, run `preflight` as the first argument. The runner
stages `ansible/cli/node.yml` and its runtime support before invoking Ansible.
