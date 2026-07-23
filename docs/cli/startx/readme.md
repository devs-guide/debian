---
title: STARTX runner
section: CLI / STARTX
source_path: setup/cli/startx.sh
script_url: https://devs-guide.github.io/debian/setup/cli/startx.sh
---

# STARTX runner

Creates the local-console X startup wiring used by a kiosk profile. Modes are
`preflight`, `apply`, and `disable`.

## Local-console STARTX wrapper

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/startx.sh | \
  env DEBIAN_STARTX_MODE=apply \
      DEBIAN_STARTX_ENABLE=1 \
      DEBIAN_STARTX_USER=app \
      DEBIAN_STARTX_TTY=tty1 \
      DEBIAN_STARTX_DISPLAY=:0 \
      DEBIAN_STARTX_INSTALL_PACKAGES=1 \
      DEBIAN_STARTX_MANAGE_XWRAPPER=1 \
      DEBIAN_STARTX_MANAGE_XINITRC=1 \
      DEBIAN_STARTX_MANAGE_WRAPPER=1 \
      DEBIAN_STARTX_WRAPPER_PATH=/usr/local/bin/kiosk-startx \
      DEBIAN_STARTX_OPENBOX_COMMAND=/usr/bin/openbox-session \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_STARTX_USER` / `DEBIAN_STARTX_TTY` / `DEBIAN_STARTX_DISPLAY` | Defines the local console identity and X display. |
| `DEBIAN_STARTX_MANAGE_XWRAPPER` | Manages the Xorg wrapper policy needed for the intended console user. |
| `DEBIAN_STARTX_MANAGE_XINITRC` / `DEBIAN_STARTX_MANAGE_WRAPPER` | Creates the managed startup files and wrapper. |
| `DEBIAN_STARTX_OPENBOX_COMMAND` | Application/session command executed at the end of the managed X startup. |
| `DEBIAN_STARTX_SERVER_ARGS` | Optional X-server arguments; the default disables TCP listening. |

The managed wrapper defaults to `/usr/local/bin/kiosk-startx`; it is intended
for a local console session, not for starting an X server over SSH.
