---
title: Hardware runner
section: Setup / Hardware
source_path: setup/hardware.sh
script_url: https://devs-guide.github.io/debian/setup/hardware.sh
---

# Hardware runner

Installs the selected source-neutral hardware baseline. Modes are `preflight`
and `apply`.

## Inspect available host policy

```bash
wget -qO- https://devs-guide.github.io/debian/setup/hardware.sh | \
  env DEBIAN_HARDWARE_MODE=preflight bash
```

## Apply an explicit host baseline

```bash
wget -qO- https://devs-guide.github.io/debian/setup/hardware.sh | \
  env DEBIAN_HARDWARE_MODE=apply \
      DEBIAN_HARDWARE_ARCHIVE_TOOLS=1 \
      DEBIAN_HARDWARE_FIRMWARE=1 \
      DEBIAN_HARDWARE_DEV_TOOLS=1 \
      DEBIAN_HARDWARE_APPLY_PERFORMANCE=0 \
      DEBIAN_HARDWARE_CPUPOWER_ENABLE=0 \
      DEBIAN_HARDWARE_USB_AUTOSUSPEND_DISABLE=0 \
      DEBIAN_HARDWARE_DISABLE_CONSOLE_BLANKING=0 \
      DEBIAN_HARDWARE_POWER_POLICY=0 \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_HARDWARE_MODE` | Selects read-only `preflight` or mutating `apply`. |
| `DEBIAN_HARDWARE_ARCHIVE_TOOLS` / `DEBIAN_HARDWARE_DEV_TOOLS` | Opts into the reviewed archive and development-tool package groups. |
| `DEBIAN_HARDWARE_FIRMWARE` | Opts into the firmware package group. Confirm the hardware/licensing policy first. |
| `DEBIAN_HARDWARE_APPLY_PERFORMANCE` | Enables the performance playbook only when explicitly set to `1`. |
| `DEBIAN_HARDWARE_CPUPOWER_ENABLE`, `DEBIAN_HARDWARE_USB_AUTOSUSPEND_DISABLE`, `DEBIAN_HARDWARE_DISABLE_CONSOLE_BLANKING`, `DEBIAN_HARDWARE_POWER_POLICY` | Individual power/console policy toggles. They remain `0` above for a conservative baseline. |

GPU vendor packages and GPU policy are deliberately outside this runner. Use
the [NVIDIA runner](/debian/cli/nvidia/) when an NVIDIA/CUDA configuration is
required.
