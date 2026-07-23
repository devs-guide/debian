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

The [reference material](/debian/kiosk/reference/) is retained for historical
device notes. It is not a substitute for the current runner documentation.
