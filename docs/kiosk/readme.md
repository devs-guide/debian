---
title: Kiosk workflow
section: Kiosk
source_path: setup/cli/kiosk.app.sh
---

# Kiosk workflow

The kiosk feature is intentionally split into small runners with explicit
ownership:

1. X11 provides the base X packages.
2. STARTX owns local-console X startup and the managed wrapper.
3. Openbox owns the session configuration.
4. Touchscreen is optional and device-specific.
5. Autologin owns the console login behavior.

Use [kiosk app](/debian/cli/kiosk.app/) to orchestrate that order, or review
the related [app launch](/debian/kiosk/app-launch/) and
[remote-debug](/debian/kiosk/remote-debug/) guidance first.

## Complete local X/Openbox kiosk profile

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

This command deliberately leaves touchscreen support off until the target
input device and display mapping have been verified. Enable it with
`DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=1` only after reviewing the
[touchscreen runner](/debian/cli/touchscreen/) controls.

The [reference material](/debian/kiosk/reference/) is retained for historical
device notes. It is not a substitute for the current runner documentation.
