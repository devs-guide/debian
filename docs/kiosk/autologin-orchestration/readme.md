---
title: Kiosk autologin orchestration
section: Kiosk / Autologin orchestration
source_path: setup/cli/kiosk.app.sh
---

# Kiosk autologin orchestration

`setup/autologin.sh` owns only TTY autologin behavior. It does not install or
configure X11, STARTX, Openbox, or touchscreen packages.

`setup/cli/kiosk.app.sh` is the opt-in orchestrator. In an apply flow it can
run X11, STARTX, Openbox, optional touchscreen configuration, and then
delegate to autologin. Use its `DEBIAN_AUTOAPP_*` controls to choose a
`command` or `startx` profile explicitly.

For a no-X text-mode console profile, disable the X11, STARTX, Openbox, and
touchscreen sub-runners rather than relying on accidental package state.

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
