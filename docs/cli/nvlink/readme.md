---
title: NVLink validation runner
section: CLI / NVLink
source_path: setup/cli/nvlink.sh
script_url: https://devs-guide.github.io/debian/setup/cli/nvlink.sh
---

# NVLink validation runner

Validates a previously installed NVIDIA/CUDA host; it does not install an
NVIDIA driver or CUDA toolkit. Modes are `preflight`, `apply`, and `validate`.

## Read-only topology check

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  sudo bash -s -- preflight --gpu=all --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 --require-nvlink --expect-topology=NV4
```

`apply` may install source-neutral build tools only when explicitly requested;
it then builds the managed smoke-test helper. P2P testing is opt-in. A passing
P2P result records hardware/runtime capability only; it does not globally
enable application P2P, unified memory, or LLM readiness.

Like the NVIDIA runner, streamed privileged runs require `sudo` on the right
side of the pipe.
