---
title: Openbox runner
section: CLI / Openbox
source_path: setup/cli/openbox.sh
script_url: https://devs-guide.github.io/debian/setup/cli/openbox.sh
---

# Openbox runner

Manages the selected user’s Openbox session integration. Modes are `preflight`,
`apply`, and `disable`.

## Managed Openbox session

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox.sh | \
  env DEBIAN_OPENBOX_MODE=apply \
      DEBIAN_OPENBOX_ENABLE=1 \
      DEBIAN_OPENBOX_USER=app \
      DEBIAN_OPENBOX_INSTALL_PACKAGES=1 \
      DEBIAN_OPENBOX_SESSION_COMMAND=/usr/bin/openbox-session \
      DEBIAN_OPENBOX_MANAGE_XINITRC=1 \
      DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR=1 \
      DEBIAN_OPENBOX_FULLSCREEN=0 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_OPENBOX_USER` | User whose Openbox/X session files are managed. |
| `DEBIAN_OPENBOX_SESSION_COMMAND` | Session executable; the default is `/usr/bin/openbox-session`. |
| `DEBIAN_OPENBOX_MANAGE_XINITRC` / `DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR` | Controls managed session startup files and hook directory. |
| `DEBIAN_OPENBOX_FULLSCREEN` | Enables the optional fullscreen helper only when explicitly set to `1`. |
| `DEBIAN_OPENBOX_FULLSCREEN_MATCH` | Window match used by that optional helper; review it before enabling fullscreen automation. |
