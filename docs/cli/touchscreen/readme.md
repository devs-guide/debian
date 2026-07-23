---
title: Touchscreen runner
section: CLI / Touchscreen
source_path: setup/cli/touchscreen.sh
script_url: https://devs-guide.github.io/debian/setup/cli/touchscreen.sh
---

# Touchscreen runner

Configures the project’s touchscreen package and session-hook layer. Modes are
`preflight`, `apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen.sh | bash
```

Device matching, output selection, and matrices are controlled through
`DEBIAN_TOUCHSCREEN_*` variables. Keep device-specific calibration changes
explicit and retain a tested configuration for the target display.
