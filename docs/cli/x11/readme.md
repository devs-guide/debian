---
title: X11 runner
section: CLI / X11
source_path: setup/cli/x11.sh
script_url: https://devs-guide.github.io/debian/setup/cli/x11.sh
---

# X11 runner

Configures the minimal X11 prerequisites used by the kiosk workflow. Modes are
`preflight`, `apply`, and `disable`.

## Install the X11 prerequisite layer

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/x11.sh | \
  env DEBIAN_X11_MODE=apply \
      DEBIAN_X11_ENABLE=1 \
      DEBIAN_X11_INSTALL_PACKAGES=1 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_X11_MODE` | Uses `preflight`, `apply`, or `disable`. |
| `DEBIAN_X11_ENABLE` | Explicitly enables or disables the managed X11 feature. |
| `DEBIAN_X11_INSTALL_PACKAGES` | Allows this runner to install its X11 package set during apply. |
| `DEBIAN_X11_PACKAGES` | Optional explicit package-list override; leave unset unless the host policy requires a reviewed change. |

Use it independently for a narrow X11 setup or let `kiosk.app.sh` orchestrate
it as part of a managed kiosk profile.
