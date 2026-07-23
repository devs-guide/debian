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

For every streamed managed mode, put `sudo` on the **right** side of the pipe.
This elevates the script that was just downloaded; it does not silently fetch a
second privileged copy.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  sudo bash -s -- preflight
```

Do not use `sudo wget ... | bash`: that elevates only `wget`, leaving the
shell on the right unprivileged. An unprivileged streamed managed mode fails
closed rather than re-downloading itself as root.

## Complete LLM-host example

The following is a concrete policy for Debian 13 (Trixie), two RTX 3090 GPUs
(SM 8.6), and a headless LLM host. Review it before use: it permits migration
from Debian’s driver packages and changes the GPU software stack.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  sudo bash -s -- apply \
    --profile=llm \
    --driver-source=nvidia \
    --cuda-source=nvidia \
    --driver-channel=production \
    --driver-branch=595 \
    --driver-version=595.71.05 \
    --cuda-version=13.1 \
    --module-flavor=open \
    --gpu=all \
    --require-gpu-count=2 \
    --require-compute-capability=8.6 \
    --persistence=auto \
    --nccl=auto \
    --allow-source-migration
```

| Flag | Purpose in this example |
| --- | --- |
| `--profile=llm` | Selects the CUDA/LLM readiness policy rather than a driver-only installation. |
| `--driver-source=nvidia` / `--cuda-source=nvidia` | Uses NVIDIA’s repository for both the driver and CUDA toolkit. |
| `--driver-channel=production` | Selects the production driver channel. |
| `--driver-branch=595` / `--driver-version=595.71.05` | Pins the intended driver family and exact package version. |
| `--cuda-version=13.1` | Requests the CUDA Toolkit 13.1 package family. |
| `--module-flavor=open` | Selects the open NVIDIA kernel-module flavor for this Ampere target. |
| `--gpu=all` | Selects all detected NVIDIA GPUs before enforcing the requirements below. |
| `--require-gpu-count=2` | Requires at least two selected GPUs. Exact two-GPU and topology enforcement belongs to the NVLink validation feature. |
| `--require-compute-capability=8.6` | Requires the RTX 3090 SM 8.6 capability. |
| `--persistence=auto` / `--nccl=auto` | Leaves these policy-controlled choices at their supported automatic settings. |
| `--allow-source-migration` | Explicitly permits replacement of an existing Debian/NVIDIA package source policy. |

CUDA 13.1 requires a compatible driver floor; the pinned 595.71.05 target is
above that floor. The repository CUDA/LLM compatibility matrix must mark CUDA
13.1 as tested or the feature fails closed instead of claiming LLM readiness.

## Verify the installed policy

Run the same selected policy in `validate` mode after installation. Keeping the
requirements in the command detects configuration drift rather than merely
checking whether `nvidia-smi` happens to start.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  sudo bash -s -- validate \
    --profile=llm \
    --driver-source=nvidia \
    --cuda-source=nvidia \
    --driver-channel=production \
    --driver-branch=595 \
    --driver-version=595.71.05 \
    --cuda-version=13.1 \
    --module-flavor=open \
    --gpu=all \
    --require-gpu-count=2 \
    --require-compute-capability=8.6 \
    --persistence=auto \
    --nccl=auto
```

`validate` refreshes NVIDIA-owned readiness facts at
`/etc/ansible/debian/facts/nvidia.yml`. It requires `nvidia-smi` for every
profile and, for `cuda` and `llm`, also requires the package-managed `nvcc`
and readable `/usr/local/cuda/include/cuda_runtime.h`. It cannot be combined
with `--skip-live-validate`; a failed validation records the live failure in
the facts rather than reporting a stale ready state.

Then confirm the driver inventory and compiler from an interactive shell:

```bash
source /etc/ansible/debian/env/llm-nvidia.sh
nvidia-smi
nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,memory.total,driver_version,compute_cap \
  --format=csv,noheader
nvcc --version
```

The managed environment fragment exports `CUDA_HOME=/usr/local/cuda` and adds
`${CUDA_HOME}/bin` to `PATH` only when both the driver and package-managed
compiler validate. It intentionally does not add a global `LD_LIBRARY_PATH`.

## Next step

NVIDIA installation alone does not prove CUDA compile/run readiness on every
physical GPU or validate the NVLink topology. For the selected RTX 3090 pair,
continue with the opt-in [NVLink validation runner](/debian/cli/nvlink/) after
the NVIDIA `validate` command succeeds.
