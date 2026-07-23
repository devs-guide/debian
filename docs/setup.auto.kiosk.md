# `setup/autologin.sh` + `setup/cli/kiosk.app.sh`

This document describes the split responsibilities:

- `setup/autologin.sh` owns only tty autologin behavior.
- `setup/cli/kiosk.app.sh` orchestrates separate feature runners (`x11`, `startx`, `openbox`, `touchscreen`) and then delegates to autologin.

## Runtime Roles

### `setup/autologin.sh`

`setup/autologin.sh` is the canonical autologin runner. It manages:

- `getty@tty1.service` override
- `/home/<user>/.config/debian/autologin-login.sh`
- managed block in `/home/<user>/.bash_profile`
- `/etc/ansible/debian/facts/autologin.yml`

It does not install X11/Openbox/STARTX/touchscreen packages.

### `setup/cli/kiosk.app.sh`

`setup/cli/kiosk.app.sh` is an orchestrator.

Default order in `apply`:

1. `setup/cli/x11.sh`
2. `setup/cli/startx.sh`
3. `setup/cli/openbox.sh`
4. `setup/cli/touchscreen.sh` (if enabled)
5. `setup/autologin.sh`

In that flow each runner receives environment overrides from `DEBIAN_AUTOAPP_*` and passes its own `DEBIAN_<FEATURE>_*` variables.

## Local vs Remote Execution

Both local file execution and published endpoint execution are equivalent:

- Local: `./setup/cli/kiosk.app.sh`
- Remote: `wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | bash`

Both modes:

- auto-install bootstrap Ansible runtime via `setup/release.common.sh`
- request `sudo` re-entry when invoked by non-root
- execute in `preflight`, `apply`, or `disable`

## Current Defaults

### `kiosk.app` defaults

- `DEBIAN_AUTOAPP_PROFILE=command`
- `DEBIAN_AUTOAPP_USER=app`
- `DEBIAN_AUTOAPP_TTY=tty1`
- `DEBIAN_AUTOAPP_COMMAND=nano` (command profile only)
- `DEBIAN_AUTOAPP_ENABLE`:
  - `0` for `disable`
  - `1` otherwise
- runner flags:
  - `DEBIAN_AUTOAPP_RUN_X11=1`
  - `DEBIAN_AUTOAPP_RUN_STARTX=1` only when profile is `startx` (0 otherwise by default)
  - `DEBIAN_AUTOAPP_RUN_OPENBOX=1`
  - `DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=0`

### Feature defaults from group vars

- X11: packages for `xserver-xorg`, `xinit`, `x11-*`, `xauth`, `wmctrl`.
- STARTX: manages `/etc/X11/Xwrapper.config`, `.xinitrc`, and `/usr/local/bin/kiosk-startx`.
- Openbox: installs/configures `.xinitrc` and optional fullscreen hook.
- Touchscreen: installs `xinput`, `xinput-calibrator`, `xserver-xorg-input-evdev` and optional `evtest`.

## Recommended Run Order

## Text-mode debug on local tty1

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_PROFILE=command \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_COMMAND='bash' \
      DEBIAN_AUTOAPP_RUN_X11=0 \
      DEBIAN_AUTOAPP_RUN_STARTX=0 \
      DEBIAN_AUTOAPP_RUN_OPENBOX=0 \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=0 \
      bash
```

No X stack is created in this mode.

## Managed X/Openbox kiosk on tty1

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash
```

This run includes:

1. X11 packages + runtime prerequisites
2. Xwrapper + wrapper command (`/usr/local/bin/kiosk-startx`)
3. Openbox session setup
4. autologin wiring to call `kiosk-startx` on tty1

## Add touchscreen in the same stack

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=1 \
      DEBIAN_TOUCHSCREEN_MATCH='eGalax|D-WAV|Titan6001|TouchController|Touchscreen' \
      bash
```

Touchscreen support can also be updated independently by running:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen | \
  env DEBIAN_TOUCHSCREEN_MODE=apply \
      DEBIAN_TOUCHSCREEN_ENABLE=1 \
      DEBIAN_TOUCHSCREEN_MATCH='eGalax|D-WAV|Titan6001|TouchController|Touchscreen' \
      bash
```

## Tauri + Kiosk

For GUI app development on the same host:

1. `setup/cli/tauri.sh` (toolchain)
2. `setup/cli/kiosk.app.sh` with `DEBIAN_AUTOAPP_PROFILE=startx` (or `command` if remote/debug only)
3. start app in autologin command for command profile

Example:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/tauri | \
  env DEBIAN_CLI_TAURI_PROFILE=build \
      DEBIAN_CLI_TAURI_INSTALL_RUNTIME=1 \
      DEBIAN_CLI_TAURI_INSTALL_BUILD_DEPS=1 \
      DEBIAN_CLI_TAURI_INSTALL_NODE=1 \
      DEBIAN_CLI_TAURI_INSTALL_RUST=1 \
      DEBIAN_CLI_TAURI_INSTALL_CLI=1 \
      DEBIAN_CLI_TAURI_CLI_METHOD=npm \
      bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_PROFILE=command \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_COMMAND='bash -lc '\''cd /opt/my-tauri-app && npm run tauri dev'\''' \
      DEBIAN_AUTOAPP_RUN_X11=0 \
      DEBIAN_AUTOAPP_RUN_STARTX=0 \
      DEBIAN_AUTOAPP_RUN_OPENBOX=0 \
      bash
```

## Notes

- `setup/autologin.sh` and `kiosk.app` do not create monitor calibration `.conf` files or compositor profiles.
- Touchscreen calibration helpers are provided, but device-specific mapping and placement tuning are still done via hook variables and optional manual override.
- For default SSH debug, use `command` profile and leave `STARTX`/`OPENBOX` disabled.
