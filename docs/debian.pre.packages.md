# debian.pre-packages

Recommended pre-install package baseline for a fresh Debian host before running
the full playbook set.

## Quick install

```sh
apt update && apt install -y \
  sudo ca-certificates gnupg curl wget \
  net-tools iproute2 openssh-server chrony \
  ufw unattended-upgrades fail2ban auditd
```

## Purpose

- establish remote access and privilege escalation
- ensure TLS/GPG bootstrap prerequisites exist
- enable time sync, firewalling, and baseline hardening
- reduce first-run bootstrap drift on older or minimal installs
