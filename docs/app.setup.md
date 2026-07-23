1. install/configure startx
2. point kiosk.app at /usr/local/bin/kiosk-startx

The current STARTX implementation always writes .xinitrc that ends with exec <DEBIAN_STARTX_OPENBOX_COMMAND>,
so the main X app is controlled by DEBIAN_STARTX_OPENBOX_COMMAND, not by DEBIAN_AUTOAPP_COMMAND once you are
in startx profile.

1. XCLOCK digital full-screen-ish kiosk

There is no first-class xclock --fullscreen mode in this repo. The supported path is to make STARTX launch a
shell that starts xclock in digital mode and then uses wmctrl to fullscreen the window.

Install STARTX and make it launch xclock:

wget -qO- https://devs-guide.github.io/debian/setup/cli/startx | \
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
      DEBIAN_STARTX_OPENBOX_COMMAND="sh -lc 'xclock -digital -update 1 -strftime \"%H:%M:%S\" -face
\"monospace-96\" & sleep 2; wmctrl -r xclock -b add,fullscreen; wait'" \
      bash

Then configure autologin to start the STARTX wrapper:

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash

Notes:

- This is “fullscreen via window manager”, not a native fullscreen mode.
- If the title match xclock is too loose on your machine, inspect the real window title with wmctrl -l and
  adjust it.

2. Tauri app kiosk

For a Tauri GUI app, use startx profile and make STARTX launch the app inside X.

First install the Tauri build/runtime stack:

wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | \
  env DEBIAN_CLI_TAURI_PROFILE=build \
      DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 \
      DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 \
      DEBIAN_CLI_TAURI_INSTALL_NODE=1 \
      DEBIAN_CLI_TAURI_INSTALL_RUST=1 \
      DEBIAN_CLI_TAURI_INSTALL_CLI=1 \
      DEBIAN_CLI_TAURI_CLI_METHOD=npm \
      bash

Then configure STARTX to launch the dev app:

wget -qO- https://devs-guide.github.io/debian/setup/cli/startx | \
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
      DEBIAN_STARTX_OPENBOX_COMMAND="sh -lc 'cd /opt/my-tauri-app && npm run tauri dev'" \
      bash

Then point kiosk.app at the wrapper:

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash

If Node is already installed and should be preserved, use DEBIAN_CLI_TAURI_INSTALL_NODE=0.

For a built Tauri binary instead of dev mode, replace DEBIAN_STARTX_OPENBOX_COMMAND with something like:

DEBIAN_STARTX_OPENBOX_COMMAND="/opt/my-tauri-app/bin/my-app"

3. Default Openbox developer/debug session

If you want the box to boot into a plain Openbox X session and then attach apps later over SSH, keep the
default Openbox command:

wget -qO- https://devs-guide.github.io/debian/setup/cli/startx | \
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

Then enable autologin into the wrapper:

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash

After the console session has started X locally, you can SSH in as the same user and launch debug apps into
that session with:

export DISPLAY=:0
export XAUTHORITY=/home/app/.Xauthority
export XDG_RUNTIME_DIR=/run/user/$(id -u app)

Then run things like:

xclock -digital -update 1 -strftime '%H:%M:%S' &
xterm &
/opt/my-tauri-app/bin/my-app &

Important constraint: /usr/local/bin/kiosk-startx intentionally refuses to start X from SSH. SSH is only for
attaching apps to an already-running local X session, not for launching the X server itself.

If you want, I can add these exact command sets into docs/kiosk.app.md.
