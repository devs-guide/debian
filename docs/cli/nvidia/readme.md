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

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Default read-only inventory and policy report. It does not request sudo or change the host. |
| `apply` | Configures the explicitly selected repository, driver, CUDA, and readiness policy. |
| `validate` | Rechecks an installed policy and refreshes NVIDIA-owned facts without changing package sources or packages. The managed Ansible controller must already exist. |
| `upgrade` | Updates only the explicitly selected, already configured NVIDIA package policy. |

The mode is a positional argument after `bash -s --`; it is not a `--mode`
flag.

## Privilege and download model

The primary streamed form is `wget | bash`. `preflight` remains unprivileged:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  bash -s -- preflight
```

For `apply`, `validate`, or `upgrade`, the downloaded runner obtains its shared
helper and then checks the current privilege session. If root is needed and no
cached or passwordless credential exists, it requests sudo exactly once
through `/dev/tty`; password input is not echoed. Every privileged command
afterward uses the cached credential with noninteractive `sudo -n`.

The runner does not re-execute itself, preserve the ambient environment, or
download a second privileged copy. Release helpers, playbooks, tasks, and
support files are staged by the original process and are never fetched from
inside a delegated sudo command.

The compatibility form remains supported for callers that intentionally start
the complete runner as root:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  sudo bash -s -- apply \
    --profile=llm \
    --driver-source=nvidia \
    --cuda-source=nvidia \
    --driver-branch=595 \
    --driver-version=595.71.05 \
    --cuda-version=13.1 \
    --module-flavor=open \
    --gpu=all \
    --require-gpu-count=2 \
    --require-compute-capability=8.6 \
    --allow-source-migration
```

Do not use `sudo wget ... | bash`: that elevates only `wget`, not the shell on
the right side. In a noninteractive session, managed modes work only with an
existing cached credential or passwordless sudo. Without either one and
without a usable `/dev/tty`, the runner fails before package or Ansible
activity. Allocate a terminal with `ssh -t`, authenticate first with
`sudo -v`, configure narrowly scoped passwordless sudo, or use the compatibility
form above.

## Complete LLM-host example

The following is a concrete policy for Debian 13 (Trixie), two RTX 3090 GPUs
(SM 8.6), and a headless LLM host. Review it before use: it permits migration
from Debian’s driver packages and changes the GPU software stack.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  bash -s -- apply \
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

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--profile=driver\|cuda\|llm` | Selects driver-only, CUDA build/runtime, or approved LLM-prerequisite policy. The example uses `llm`. |
| `--driver-source=auto\|debian\|nvidia` | Selects the driver package source. Mutating CUDA/LLM requests must resolve to an explicit supported source. |
| `--cuda-source=none\|auto\|debian\|nvidia` | Selects the toolkit source. `none` is valid only for the driver profile. |
| `--driver-channel=production\|new-feature` | Selects the driver channel. `new-feature` requires an explicit branch. |
| `--driver-branch=<branch>` | Restricts driver resolution to a numeric branch such as `595`. Production currently defaults to branch 595. |
| `--driver-version=<exact-version>` | Pins an exact driver package version, such as `595.71.05`; it cannot be combined with `--latest-in-branch`. |
| `--cuda-version=<major.minor>` | Selects an exact approved toolkit minor such as `13.1`; CUDA/LLM apply requires it. |
| `--module-flavor=auto\|open\|proprietary` | Selects the kernel-module policy. The example explicitly uses the open Ampere-supported flavor. |
| `--gpu=all\|<UUID-or-PCI-list>` | Selects all GPUs or a comma-separated stable UUID/PCI list. UUIDs are preferred over mutable indices. |
| `--require-gpu-count=<count>` | Requires at least this many selected GPUs. Exact count and topology gates belong to NVLink validation. |
| `--require-compute-capability=<list>` | Requires every selected GPU to match one of the comma-separated `major.minor` values. |
| `--persistence=auto\|on\|off` | Records the requested persistence policy. |
| `--nccl=auto\|on\|off` | Records the requested NCCL prerequisite policy; it does not prove application-level distributed correctness. |
| `--run-p2p-test` | Parsed as a compatibility policy input; this installation runner does not execute or claim the standalone P2P diagnostic. Use the NVLink runner instead. |
| `--allow-source-migration` | Explicitly permits replacement of an existing Debian/NVIDIA package-source policy. |
| `--allow-no-gpu` | Records a no-GPU policy input; it does not make CUDA/LLM live validation pass without required hardware. |
| `--allow-cuda-minor-compat` | Records minor-compatibility policy while retaining the repository’s tested matrix and driver-floor gates. |
| `--skip-live-validate` | Apply/upgrade-only escape hatch. It cannot be used with `validate` and cannot produce a fresh live-ready validation result. |
| `--check-upstream` | Parsed as a reserved upstream-check policy input. The current playbook still resolves only configured APT metadata and does not authorize an unpinned transaction. |
| `--latest-in-branch` | Selects the highest APT candidate inside the resolved pinned branch; it cannot be combined with an exact driver version. |
| `--help` | Prints runner usage without staging or changing the host. |

CUDA 13.1 requires a compatible driver floor; the pinned 595.71.05 target is
above that floor. The repository CUDA/LLM compatibility matrix must mark CUDA
13.1 as tested or the feature fails closed instead of claiming LLM readiness.

## Verify the installed policy

Run the same selected policy in `validate` mode after installation. Keeping the
requirements in the command detects configuration drift rather than merely
checking whether `nvidia-smi` happens to start.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvidia.sh | \
  bash -s -- validate \
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

## Fact ownership and migration

The NVIDIA feature exclusively owns
`/etc/ansible/debian/facts/nvidia.yml`. Schema version 1 records the selected
validation policy plus observed driver, CUDA, inventory, and readiness state.
NVLink never writes this file directly.

At the beginning of every managed NVLink run, NVLink imports NVIDIA in
internal `validate-from-facts` mode. NVIDIA reads its own recorded policy,
performs live validation, and atomically refreshes its fact file before NVLink
rereads it. Older schema-1 facts that predate `validation_policy` are
reconstructed from their recorded profile, source, driver, CUDA, and inventory
fields; a successful refresh persists the complete policy. Missing, malformed,
or unsupported-schema facts fail closed. Re-run the complete NVIDIA `apply`
command above to initialize a valid policy rather than editing the fact file.

## Next step

NVIDIA installation alone does not prove CUDA compile/run readiness on every
physical GPU or validate the NVLink topology. For the selected RTX 3090 pair,
continue with the opt-in [NVLink validation runner](/debian/cli/nvlink/).
Managed NVLink runs automatically invoke NVIDIA validate mode from the
NVIDIA-owned fact policy before CUDA/NVLink testing; running NVIDIA `validate`
directly remains useful for inspecting driver/CUDA readiness by itself.
