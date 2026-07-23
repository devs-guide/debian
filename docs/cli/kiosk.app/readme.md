---
title: Kiosk app runner
section: CLI / Kiosk app
source_path: setup/cli/kiosk.app.sh
script_url: https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh
---

# Kiosk app runner

Orchestrates the kiosk feature runners and then delegates console autologin.
Its modes are `preflight`, `apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/kiosk.app.sh | bash
```

The supported roles and ordering are documented in the [kiosk
guide](/debian/kiosk/). Set the `DEBIAN_AUTOAPP_*` variables explicitly when
selecting a `command` or `startx` profile.
