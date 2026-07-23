---
title: Essential package reference
section: Setup / Essential packages
source_path: ansible/install.packages.yml
---

# Essential package reference

For a manual minimal baseline before using Ansible:

```sh
sudo apt update && sudo apt install -y \
  sudo ca-certificates gnupg curl wget \
  python3 python3-apt python3-venv \
  openssh-server chrony ufw fail2ban auditd \
  git net-tools iproute2 htop smartmontools
```

The maintained grouped package policy is implemented by
`ansible/install.packages.yml`; use it rather than treating this line as a
complete host policy. The command installs only its named baseline packages;
it does not enable every optional Ansible package group.
