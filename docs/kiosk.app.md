# `kiosk.app`

`kiosk.app` is the orchestration entry for kiosk-style setup on Debian.
It coordinates these feature runners and then applies autologin:

- `setup/cli/x11.sh` → `ansible/cli/x11.yml`
- `setup/cli/startx.sh` → `ansible/cli/startx.yml`
- `setup/cli/openbox.sh` → `ansible/cli/openbox.yml`
- `setup/cli/touchscreen.sh` → `ansible/cli/touchscreen.yml`
- `setup/autologin.sh` → `ansible/autologin.yml`

You can run all of this through:

- Local: `./setup/cli/kiosk.app.sh [preflight|apply|disable]`
- Remote: `wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | bash`

It is non-root friendly: both it and all delegated CLI runners request `sudo` re-entry when needed.

## Flow Diagram

```text
entry
├── local
│   └── ./setup/cli/kiosk.app.sh [preflight|apply|disable]
└── web
    └── wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | bash
        └── same kiosk.app shell logic from published static copy

kiosk.app
├── parse args / mode / profile
├── normalize defaults
│   ├── DEBIAN_AUTOAPP_MODE (preflight|apply|disable)
│   ├── DEBIAN_AUTOAPP_PROFILE (command|startx)
│   ├── DEBIAN_AUTOAPP_RUN_X11 (default: 1 on all modes)
│   ├── DEBIAN_AUTOAPP_RUN_STARTX (default: 1 only when profile=startx)
│   ├── DEBIAN_AUTOAPP_RUN_OPENBOX (default: 1)
│   └── DEBIAN_AUTOAPP_RUN_TOUCHSCREEN (default: 0)
├── optional root re-exec via sudo
├── resolve feature env for each enabled runner
│   ├── x11 runner env (packages + runtime facts)
│   ├── startx runner env (wrapper, xinitrc, x11 policy)
│   ├── openbox runner env (session hook + fullscreen helper)
│   ├── touchscreen runner env (xinput helpers + runtime config)
│   └── autologin env (command after login)
├── call delegated features in order
│   ├── setup/cli/x11.sh
│   ├── setup/cli/startx.sh
│   ├── setup/cli/openbox.sh
│   └── setup/cli/touchscreen.sh
└── call autologin
    └── setup/autologin.sh (forced action=command)
```

## Defaults and Profiles

- `DEBIAN_AUTOAPP_ENABLE`: auto-enabled unless explicitly `0`/`1` and not overridden by mode.
- `DEBIAN_AUTOAPP_PROFILE=command` (default): no X autostart. Default command is `nano`.
- `DEBIAN_AUTOAPP_PROFILE=startx`: `DEBIAN_AUTOAPP_COMMAND` defaults to `/usr/local/bin/kiosk-startx`.
- `DEBIAN_AUTOAPP_RUN_*`: override to skip individual feature runners.

`command` profile does not allow obvious direct-`startx` command patterns, to avoid running X directly from tty/SSH.

## Core Parameters

### Orchestrator

- `DEBIAN_AUTOAPP_MODE`
- `DEBIAN_AUTOAPP_ENABLE`
- `DEBIAN_AUTOAPP_USER`
- `DEBIAN_AUTOAPP_TTY`
- `DEBIAN_AUTOAPP_TERM`
- `DEBIAN_AUTOAPP_NORESET`
- `DEBIAN_AUTOAPP_NOCLEAR`
- `DEBIAN_AUTOAPP_PROFILE` (`command` | `startx`)
- `DEBIAN_AUTOAPP_COMMAND`
- `DEBIAN_AUTOAPP_STARTX_DEFAULT_COMMAND`
- `DEBIAN_AUTOAPP_MARKER_ENABLE`
- `DEBIAN_AUTOAPP_MARKER_PATH`
- `DEBIAN_AUTOAPP_RUNTIME_FACTS_PATH`
- `DEBIAN_AUTOAPP_RUN_X11`
- `DEBIAN_AUTOAPP_RUN_STARTX`
- `DEBIAN_AUTOAPP_RUN_OPENBOX`
- `DEBIAN_AUTOAPP_RUN_TOUCHSCREEN`
- `DEBIAN_AUTOAPP_SUDO_REEXEC` (internal)
- `DEBIAN_AUTOAPP_SELF_URL`

### Feature passthrough examples

#### X11 stack

- `DEBIAN_X11_INSTALL_PACKAGES` (default: 1)
- `DEBIAN_X11_PACKAGES`
- `DEBIAN_X11_RUNTIME_FACTS_PATH`

#### STARTX

- `DEBIAN_STARTX_ENABLE`
- `DEBIAN_STARTX_TTY`
- `DEBIAN_STARTX_DISPLAY`
- `DEBIAN_STARTX_MANAGE_XWRAPPER`
- `DEBIAN_STARTX_ALLOWED_USERS`
- `DEBIAN_STARTX_NEEDS_ROOT_RIGHTS`
- `DEBIAN_STARTX_MANAGE_XINITRC`
- `DEBIAN_STARTX_MANAGE_WRAPPER`
- `DEBIAN_STARTX_WRAPPER_PATH`
- `DEBIAN_STARTX_XINITRC_PATH`
- `DEBIAN_STARTX_XSESSION_HOOK_DIR`
- `DEBIAN_STARTX_OPENBOX_COMMAND`
- `DEBIAN_STARTX_SERVER_ARGS`

#### Openbox

- `DEBIAN_OPENBOX_USER`
- `DEBIAN_OPENBOX_SESSION_COMMAND`
- `DEBIAN_OPENBOX_XINITRC_PATH`
- `DEBIAN_OPENBOX_XSESSION_HOOK_DIR`
- `DEBIAN_OPENBOX_FULLSCREEN`
- `DEBIAN_OPENBOX_FULLSCREEN_MATCH`
- `DEBIAN_OPENBOX_FULLSCREEN_RETRIES`
- `DEBIAN_OPENBOX_FULLSCREEN_DELAY_MS`

#### Touchscreen

- `DEBIAN_TOUCHSCREEN_USER`
- `DEBIAN_TOUCHSCREEN_MATCH`
- `DEBIAN_TOUCHSCREEN_PRIMARY_ID`
- `DEBIAN_TOUCHSCREEN_DISABLE_IDS`
- `DEBIAN_TOUCHSCREEN_OUTPUT`
- `DEBIAN_TOUCHSCREEN_MATRIX`
- `DEBIAN_TOUCHSCREEN_CUSTOM_MATRIX`
- `DEBIAN_TOUCHSCREEN_CONFIG_FILE`
- `DEBIAN_TOUCHSCREEN_APPLY_SCRIPT_PATH`
- `DEBIAN_TOUCHSCREEN_LIST_SCRIPT_PATH`

## Common Use Cases

### 1) Command-mode debug session (no X autostart)

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=command \
      DEBIAN_AUTOAPP_COMMAND='bash -lc '\''cd /opt/my-tauri-app && npm run tauri dev'\''' \
      DEBIAN_AUTOAPP_RUN_X11=0 \
      DEBIAN_AUTOAPP_RUN_STARTX=0 \
      DEBIAN_AUTOAPP_RUN_OPENBOX=0 \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=0 \
      bash
```

### 2) Local X/Openbox start (STARTX profile)

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/x11 | \
  env DEBIAN_X11_MODE=apply \
      DEBIAN_X11_ENABLE=1 \
      DEBIAN_X11_INSTALL_PACKAGES=1 \
      bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/startx | \
  env DEBIAN_STARTX_MODE=apply \
      DEBIAN_STARTX_ENABLE=1 \
      DEBIAN_STARTX_TTY=tty1 \
      DEBIAN_STARTX_DISPLAY=:0 \
      DEBIAN_STARTX_WRAPPER_PATH=/usr/local/bin/kiosk-startx \
      bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox | \
  env DEBIAN_OPENBOX_MODE=apply \
      DEBIAN_OPENBOX_ENABLE=1 \
      DEBIAN_OPENBOX_FULLSCREEN=1 \
      bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash
```

### 3) One-step setup for full stack (autologin + x11/startx/openbox)

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_USER=app \
      DEBIAN_AUTOAPP_TTY=tty1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      bash
```

`kiosk.app` will call each feature runner with internal defaults before autologin.

### 4) Add touchscreen

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app | \
  env DEBIAN_AUTOAPP_MODE=apply \
      DEBIAN_AUTOAPP_ENABLE=1 \
      DEBIAN_AUTOAPP_PROFILE=startx \
      DEBIAN_AUTOAPP_COMMAND=/usr/local/bin/kiosk-startx \
      DEBIAN_AUTOAPP_RUN_TOUCHSCREEN=1 \
      bash

wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen | \
  env DEBIAN_TOUCHSCREEN_MODE=apply \
      DEBIAN_TOUCHSCREEN_ENABLE=1 \
      DEBIAN_TOUCHSCREEN_MATCH='eGalax|D-WAV|Titan6001|TouchController|Touchscreen' \
      bash
```

## What `kiosk.app` does at runtime

- creates / refreshes:
  - `/usr/local/bin/kiosk-startx` (via startx runner)
  - managed `.xinitrc` and `~/.config/debian/xsession.d` hooks (via startx/openbox runners)
  - `ansible` runtime variables/scripts for touchscreen if enabled
- configures `getty@tty1` autologin and command behavior via `autologin`
- writes feature-specific runtime facts:
  - `/etc/ansible/debian/facts/x11.yml`
  - `/etc/ansible/debian/facts/startx.yml`
  - `/etc/ansible/debian/facts/openbox.yml`
  - `/etc/ansible/debian/facts/touchscreen.yml`
  - `/etc/ansible/debian/facts/autologin.yml`

## Fullscreen app workflow

To make a session app fullscreen on startup, use Openbox fullscreen mode:

- set `DEBIAN_OPENBOX_FULLSCREEN=1`
- set `DEBIAN_OPENBOX_FULLSCREEN_MATCH='xclock'` (or target class/title)
- install `wmctrl` (included in x11 defaults)

Example:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox | \
  env DEBIAN_OPENBOX_FULLSCREEN=1 \
      DEBIAN_OPENBOX_FULLSCREEN_MATCH='xclock' \
      DEBIAN_OPENBOX_ENABLE=1 \
      bash
```

Then from SSH, after local X is running:

```bash
export DISPLAY=:0
export XAUTHORITY=/home/app/.Xauthority
export XDG_RUNTIME_DIR=/run/user/$(id -u app)
xclock -digital -update 1 -strftime '%H:%M:%S' &
```
