---
title: NVIDIA driver and CUDA runner
section: CLI / NVIDIA
source_path: setup/cli/nvidia.sh
script_url: https://devs-guide.github.io/debian/setup/cli/nvidia.sh
---

# NVIDIA driver and CUDA runner

Configures an explicit NVIDIA driver/CUDA policy. It supports `preflight`,
`apply`, `validate`, and `upgrade`. GPU installation is opt-in and remains
outside the baseline hardware runner.

## Privileged streamed use

For an `apply` operation from the published source, place `sudo` on the right
side of the pipe:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  sudo bash -s -- preflight
```

An unprivileged streamed managed mode fails closed instead of downloading a
second copy as root. Run `preflight` first, then provide the profile, source,
driver, CUDA, and GPU requirements required by the target host.

The runner manages `CUDA_HOME` and `PATH` only after compiler validation. It
does not add a global `LD_LIBRARY_PATH`.
