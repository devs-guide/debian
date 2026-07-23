# debian.users

User creation is driven by `user_defs` in `ansible/group_vars/all.yml`.

Default accounts:

- `root`
- `agent`
- `app`
- `gpt`
- `admin`

Each account defaults to:

- shell: `/bin/bash`
- password: the username itself

Group defaults:

- `root`: existing privileged account
- `agent`, `app`, `gpt`, and `admin`: `sudo`

SSH access is managed separately by `ansible/network.yml`, which always
keeps `root` in the final `AllowUsers` list to reduce lockout risk.
