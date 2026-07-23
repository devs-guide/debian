---
title: Bootstrap prerequisites
section: Setup / Prerequisites
source_path: setup/bootstrap.sh
---

# Bootstrap prerequisites

On a minimal Debian host, establish basic network access and package metadata
before first bootstrap when necessary:

```sh
apt update && apt install -y \
  sudo ca-certificates gnupg curl wget \
  net-tools iproute2 openssh-server chrony \
  ufw unattended-upgrades fail2ban auditd
```

Then use the [bootstrap runner](/debian/setup/bootstrap/). This manual list is
an operational aid, not a replacement for the managed package policy.
