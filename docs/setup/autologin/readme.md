---
title: Autologin runner
section: Setup / Autologin
source_path: setup/autologin.sh
script_url: https://devs-guide.github.io/debian/setup/autologin.sh
---

# Autologin runner

Manages console autologin only. It does not install X11, Openbox, STARTX, or
touchscreen software. Modes are `preflight`, `apply`, and `disable`.

## TTY command profile

```bash
wget -qO- https://devs-guide.github.io/debian/setup/autologin.sh | \
  env DEBIAN_AUTOLOGIN_MODE=apply \
      DEBIAN_AUTOLOGIN_ENABLE=1 \
      DEBIAN_AUTOLOGIN_USER=app \
      DEBIAN_AUTOLOGIN_TTY=tty1 \
      DEBIAN_AUTOLOGIN_ACTION=command \
      DEBIAN_AUTOLOGIN_COMMAND='/bin/bash' \
      DEBIAN_AUTOLOGIN_VALIDATION_BANNER=1 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_AUTOLOGIN_MODE` | Uses `preflight`, `apply`, or `disable`. |
| `DEBIAN_AUTOLOGIN_ENABLE` | Explicitly enables or disables the TTY autologin behavior. |
| `DEBIAN_AUTOLOGIN_USER` / `DEBIAN_AUTOLOGIN_TTY` | Identifies the managed account and console. |
| `DEBIAN_AUTOLOGIN_ACTION` / `DEBIAN_AUTOLOGIN_COMMAND` | Selects the post-login action and command. Use a reviewed local executable, not an unquoted ad-hoc shell fragment. |
| `DEBIAN_AUTOLOGIN_VALIDATION_BANNER` | Keeps the managed validation banner visible in this example. |

To remove the configuration, use the same user and TTY with
`DEBIAN_AUTOLOGIN_MODE=disable DEBIAN_AUTOLOGIN_ENABLE=0`.

For a composed desktop/kiosk workflow, use the [kiosk app
runner](/debian/cli/kiosk.app/) instead of manually assuming its feature
ordering.
