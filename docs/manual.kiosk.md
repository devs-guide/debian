#  For an X11 debug box that boots locally into Openbox on tty1 and lets you attach Python, Node, or Tauri apps over SSH, run these on the remote Debian kiosk server in this order:

wget -qO- https://devs-guide.github.io/debian/setup/cli/x11 | env DEBIAN_X11_MODE=apply DEBIAN_X11_ENABLE=1 DEBIAN_X11_INSTALL_PACKAGES=1 bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/startx | env DEBIAN_STARTX_MODE=apply DEBIAN_STARTX_ENABLE=1 DEBIAN_STARTX_USER=app DEBIAN_STARTX_TTY=tty1 DEBIAN_STARTX_DISPLAY=:0 DEBIAN_STARTX_INSTALL_PACKAGES=0 DEBIAN_STARTX_MANAGE_XWRAPPER=1 DEBIAN_STARTX_MANAGE_XINITRC=1 DEBIAN_STARTX_MANAGE_WRAPPER=1 DEBIAN_STARTX_WRAPPER_PATH=/user/local/bin/kiosk-startx DEBIAN_STARTX_OPENBOX_COMMAND=/usr/bin/openbox-session bash


wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox | env DEBIAN_OPENBOX_MODE=apply DEBIAN_OPENBOX_ENABLE=1 DEBIAN_OPENBOX_USER=app DEBIAN_OPENBOX_INSTALL_PACKAGES=1 DEBIAN_OPENBOX_SESSION_COMMAND=/usr/bin/openbox-session DEBIAN_OPENBOX_MANAGE_XSESSION_HOOK_DIR=1 DEBIAN_OPENBOX_FULLSCREEN=0 bash


#   Optional touchscreen layer:

wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen | env DEBIAN_TOUCHSCREEN_MODE=apply DEBIAN_TOUCHSCREEN_ENABLE=1 DEBIAN_TOUCHSCREEN_USER=app DEBIAN_TOUCHSCREEN_INSTALL_PACKAGES=1 DEBIAN_TOUCHSCREEN_MATCH='eGalax|D-WAV|Titan6001|TouchController|Touchscreen' bash


#   Then enable autologin so the local tty1 session launches the managed wrapper:

wget -qO- https://devs-guide.github.io/debian/setup/autologin | env DEBIAN_AUTOLOGIN_MODE=apply DEBIAN_AUTOLOGIN_ENABLE=1 DEBIAN_AUTOLOGIN_USER=app DEBIAN_AUTOLOGIN_TTY=tty1 DEBIAN_AUTOLOGIN_ACTION=command DEBIAN_AUTOLOGIN_COMMAND=/usr/local/bin/kiosk-startx DEBIAN_AUTOLOGIN_VALIDATION_BANNER=0 bash


#   For Tauri development on the same host, install the toolchain separately:


wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | env DEBIAN_CLI_TAURI_PROFILE=build DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 DEBIAN_CLI_TAURI_INSTALL_NODE=1 DEBIAN_CLI_TAURI_INSTALL_RUST=1 DEBIAN_CLI_TAURI_INSTALL_CLI=1 DEBIAN_CLI_TAURI_CLI_METHOD=npm bash


#  After the machine reboots or app logs in on tty1, SSH in and attach apps to the running X session with:

export DISPLAY=:0
export XAUTHORITY=/home/app/.Xauthority
export XDG_RUNTIME_DIR=/run/user/$(id -u app)


# TEST COMMANDS (POST INSTALL)

python3 /opt/my-app/app.py
npm run tauri dev


## TAURI

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | env DEBIAN_AUTOAPP_MODE=apply DEBIAN_AUTOAPP_ENABLE=1 DEBIAN_AUTOAPP_USER=app DEBIAN_AUTOAPP_TTY=tty1 DEBIAN_AUTOAPP_PROFILE=startx DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx DEBIAN_AUTOAPP_RUN_X11=1 DEBIAN_AUTOAPP_RUN_STARTX=1 DEBIAN_AUTOAPP_RUN_OPENBOX=1 DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=1 bash






















