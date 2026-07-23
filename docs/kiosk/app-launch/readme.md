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

## Set a reviewed local application command

The following STARTX policy keeps the standard local console setup while
launching an already-installed application binary in place of the default
Openbox session command:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/startx.sh | \
  env DEBIAN_STARTX_MODE=apply \
      DEBIAN_STARTX_ENABLE=1 \
      DEBIAN_STARTX_USER=app \
      DEBIAN_STARTX_TTY=tty1 \
      DEBIAN_STARTX_DISPLAY=:0 \
      DEBIAN_STARTX_MANAGE_XWRAPPER=1 \
      DEBIAN_STARTX_MANAGE_XINITRC=1 \
      DEBIAN_STARTX_MANAGE_WRAPPER=1 \
      DEBIAN_STARTX_WRAPPER_PATH=/usr/local/bin/kiosk-startx \
      DEBIAN_STARTX_OPENBOX_COMMAND=/opt/my-tauri-app/bin/my-app \
      bash
```

Replace only `/opt/my-tauri-app/bin/my-app` with the verified local executable.
The other values are the explicit local-console STARTX policy.
