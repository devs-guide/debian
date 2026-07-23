---
title: STARTX runner
section: CLI / STARTX
source_path: setup/cli/startx.sh
script_url: https://devs-guide.github.io/debian/setup/cli/startx.sh
---

# STARTX runner

Creates the local-console X startup wiring used by a kiosk profile. Modes are
`preflight`, `apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/startx.sh | bash
```

The managed wrapper defaults to `/usr/local/bin/kiosk-startx`; it is intended
for a local console session, not for starting an X server over SSH.
