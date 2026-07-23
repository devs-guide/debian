---
title: Kiosk application launch
section: Kiosk / Application launch
source_path: setup/cli/startx.sh
---

# Kiosk application launch

In the STARTX profile, the terminal X application is controlled by
`DEBIAN_STARTX_OPENBOX_COMMAND`. The autologin/kiosk runner points the local
console session at the managed STARTX wrapper; it does not replace the X
application command.

For a Tauri development session, install the optional Tauri toolchain first,
then configure STARTX with a command appropriate to the checked-out
application. Treat developer commands and long-lived kiosk launch commands as
separate deployment choices.

The managed wrapper intentionally refuses to start X from SSH. SSH can attach
an application to an already-running local X display only after the local
console session has established it.
