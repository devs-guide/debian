---
title: Hardware runner
section: Setup / Hardware
source_path: setup/hardware.sh
script_url: https://devs-guide.github.io/debian/setup/hardware.sh
---

# Hardware runner

Installs the selected source-neutral hardware baseline. Modes are `preflight`
and `apply`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/hardware.sh | bash
```

GPU vendor packages and GPU policy are deliberately outside this runner. Use
the [NVIDIA runner](/debian/cli/nvidia/) when an NVIDIA/CUDA configuration is
required.
