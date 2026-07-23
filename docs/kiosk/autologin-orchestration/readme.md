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
