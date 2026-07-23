---
title: Autologin runner
section: Setup / Autologin
source_path: setup/autologin.sh
script_url: https://devs-guide.github.io/debian/setup/autologin.sh
---

# Autologin runner

Manages console autologin only. It does not install X11, Openbox, STARTX, or
touchscreen software. Modes are `preflight`, `apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/autologin.sh | bash
```

For a composed desktop/kiosk workflow, use the [kiosk app
runner](/debian/cli/kiosk.app/) instead of manually assuming its feature
ordering.
