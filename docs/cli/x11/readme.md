---
title: X11 runner
section: CLI / X11
source_path: setup/cli/x11.sh
script_url: https://devs-guide.github.io/debian/setup/cli/x11.sh
---

# X11 runner

Configures the minimal X11 prerequisites used by the kiosk workflow. Modes are
`preflight`, `apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/x11.sh | bash
```

Use it independently for a narrow X11 setup or let `kiosk.app.sh` orchestrate
it as part of a managed kiosk profile.
