# install-essential-packages

If you want a single manual install line before using Ansible, this is the
smallest practical baseline:

```sh
apt update && apt install -y \
  sudo ca-certificates gnupg curl wget \
  python3 python3-apt python3-venv \
  openssh-server chrony ufw fail2ban auditd \
  git net-tools iproute2 htop smartmontools
```

For the full grouped install policy, use:

```sh
ansible-playbook ansible/install.packages.yml
```
