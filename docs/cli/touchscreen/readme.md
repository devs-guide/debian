---
title: Touchscreen runner
section: CLI / Touchscreen
source_path: setup/cli/touchscreen.sh
script_url: https://devs-guide.github.io/debian/setup/cli/touchscreen.sh
---

# Touchscreen runner

Configures the project’s touchscreen package and session-hook layer. Modes are
`preflight`, `apply`, and `disable`.

## Touchscreen hook with identity mapping

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/touchscreen.sh | \
  env DEBIAN_TOUCHSCREEN_MODE=apply \
      DEBIAN_TOUCHSCREEN_ENABLE=1 \
      DEBIAN_TOUCHSCREEN_USER=app \
      DEBIAN_TOUCHSCREEN_INSTALL_PACKAGES=1 \
      DEBIAN_TOUCHSCREEN_MATCH='eGalax|D-WAV|Titan6001|TouchController|Touchscreen' \
      DEBIAN_TOUCHSCREEN_MATRIX=identity \
      DEBIAN_TOUCHSCREEN_INSTALL_EVTEST=1 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_TOUCHSCREEN_MATCH` | Regular expression used to select the intended input device. Review against `xinput` output on the target. |
| `DEBIAN_TOUCHSCREEN_PRIMARY_ID` / `DEBIAN_TOUCHSCREEN_DISABLE_IDS` | Optional explicit X input IDs; do not persist IDs until the host inventory is known. |
| `DEBIAN_TOUCHSCREEN_OUTPUT` | Optional display output to map the selected device to. |
| `DEBIAN_TOUCHSCREEN_MATRIX` | Uses `identity` here; use `custom` only with a reviewed `DEBIAN_TOUCHSCREEN_CUSTOM_MATRIX`. |
| `DEBIAN_TOUCHSCREEN_INSTALL_EVTEST` | Installs `evtest` for device diagnostics. |

Device matching, output selection, and matrices are controlled through
`DEBIAN_TOUCHSCREEN_*` variables. Keep device-specific calibration changes
explicit and retain a tested configuration for the target display.
