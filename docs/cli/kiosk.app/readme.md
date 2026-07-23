---
title: Kiosk app runner
section: CLI / Kiosk app
source_path: setup/cli/kiosk.app.sh
script_url: https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh
---

# Kiosk app runner

Orchestrates the kiosk feature runners and then delegates console autologin.
Its modes are `preflight`, `apply`, and `disable`.

## Text-console profile

This conservative example creates an autologin command profile without
installing or configuring X11 components.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=command \
      DEBIAN_AUTOAPP_COMMAND='/bin/bash' \
      DEBIAN_AUTOAPP_RUN_X11=0 \
      DEBIAN_AUTOAPP_RUN_STARTX=0 \
      DEBIAN_AUTOAPP_RUN_OPENBOX=0 \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=0 \
      bash
```

## Local X/Openbox profile

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      DEBIAN_AUTOAPP_RUN_X11=1 \
      DEBIAN_AUTOAPP_RUN_STARTX=1 \
      DEBIAN_AUTOAPP_RUN_OPENBOX=1 \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=0 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_AUTOAPP_MODE` | Uses `preflight`, `apply`, or `disable`. |
| `DEBIAN_AUTOAPP_PROFILE` | Chooses a text `command` profile or local-console `startx` profile. |
| `DEBIAN_AUTOAPP_USER` / `DEBIAN_AUTOAPP_TTY` | Selects the managed user and TTY. |
| `DEBIAN_AUTOAPP_COMMAND` | Command for the profile; STARTX uses the managed wrapper path. |
| `DEBIAN_AUTOAPP_RUN_*` | Explicitly selects the feature runners that the orchestrator invokes. |

The supported roles and ordering are documented in the [kiosk
guide](/debian/kiosk/). Use `disable` with the same user/TTY selection when
removing the managed autologin behavior.
