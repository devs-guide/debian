---
title: NVLink validation runner
section: CLI / NVLink
source_path: setup/cli/nvlink.sh
script_url: https://devs-guide.github.io/debian/setup/cli/nvlink.sh
---

# NVLink validation runner

Validates a previously installed NVIDIA/CUDA host; it does not install an
NVIDIA driver or CUDA toolkit. Every managed `apply` or `validate` run first
uses the canonical NVIDIA validator to refresh NVIDIA-owned readiness facts
from the current driver, compiler, and CUDA-header state. Modes are
`preflight`, `apply`, and `validate`.

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Default read-only inventory, compiler, topology, and link report. It does not request sudo or enforce the managed CUDA/P2P gates. |
| `apply` | Refreshes NVIDIA facts, optionally installs source-neutral build tools, builds managed helpers, and executes the requested validation gates. |
| `validate` | Refreshes NVIDIA facts and reruns existing managed helpers without installing build tools, fetching official samples, or changing NVIDIA/CUDA packages. |

## Privilege and download model

Use the primary `wget | bash` form. The read-only preflight does not need root:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- preflight --gpu=all
```

For `apply` and `validate`, the runner requests sudo once through `/dev/tty`
only when root is required and no cached/passwordless credential exists.
Password input is not echoed. Subsequent privileged commands use
noninteractive `sudo -n`; the runner and its downloaded dependencies are not
re-fetched or executed through sudo.

`wget | sudo bash` remains a compatibility form for intentionally starting the
whole runner as root:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  sudo bash -s -- apply \
    --gpu=all \
    --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 \
    --require-nvlink \
    --expect-topology=NV4 \
    --run-p2p-test \
    --strict-p2p \
    --p2p-buffer-mib=256 \
    --p2p-iterations=20 \
    --official-samples=off \
    --install-build-tools
```

Do not use `sudo wget ... | bash`. In a noninteractive session, provide a
cached/passwordless sudo credential or allocate a terminal with `ssh -t`.
Otherwise, the managed run fails before package or Ansible activity. Interactive
`--select-gpus` also requires `/dev/tty`; automation should pass stable GPU
UUIDs with `--gpu=GPU-...,GPU-...`.

## Complete dual-RTX-3090 validation

Run this after the NVIDIA runner has installed the selected driver/CUDA policy.
Before NVLink testing, the managed run automatically revalidates that policy
and refreshes `/etc/ansible/debian/facts/nvidia.yml` plus the shared GPU
snapshot at `/etc/ansible/debian/facts/gpu.yml`; it then compiles the
managed CUDA smoke helper, tests each selected GPU by UUID, records NVLink
topology, and runs the opt-in P2P diagnostic.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- apply \
    --gpu=all \
    --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 \
    --require-nvlink \
    --expect-topology=NV4 \
    --run-p2p-test \
    --strict-p2p \
    --p2p-buffer-mib=256 \
    --p2p-iterations=20 \
    --official-samples=fetch \
    --cuda-samples-tag=v13.1 \
    --install-build-tools
```

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--gpu=all\|<UUID-or-PCI-list>` | Selects all GPUs or an explicit comma-separated physical-GPU list from the shared GPU snapshot. UUIDs select CUDA visibility; canonical PCI identifiers select physical devices. |
| `--select-gpus` | Prompts on `/dev/tty` and converts selected inventory rows to UUIDs. It cannot be combined with `--gpu`. |
| `--require-gpu-count=<minimum>` | Requires at least this many selected GPUs. |
| `--require-exact-gpu-count=<count>` | Requires precisely this many selected physical GPUs. |
| `--require-compute-capability=<list>` | Requires each selected GPU to match one of the comma-separated `major.minor` capabilities. |
| `--require-nvlink` | Makes inactive or PCIe-only transport fatal and requires `--run-p2p-test` so both directed CUDA peer checks are proven. |
| `--expect-topology=NV#` | Requires a specific topology token, such as `NV4`. `NV4` means four bonded NVLink links, not pooled VRAM. |
| `--run-p2p-test` | Runs the bounded P2P helper for exactly two explicitly selected physical GPUs. |
| `--strict-p2p` | Makes a requested P2P failure fatal; it requires `--run-p2p-test`. |
| `--p2p-buffer-mib=<size>` | Sets the positive per-transfer diagnostic buffer size. The example uses 256 MiB. |
| `--p2p-iterations=<count>` | Sets the positive bounded iteration count. The example uses 20. |
| `--official-samples=off\|existing\|fetch` | Disables official samples, uses an existing checkout, or fetches one during `apply`. `validate` rejects `fetch`. |
| `--cuda-samples-path=<path>` | Selects the managed/existing CUDA Samples checkout path. |
| `--cuda-samples-tag=v13.1` | Pins the only currently accepted CUDA Samples revision for CUDA Toolkit 13.1. |
| `--strict-official-samples` | Makes a requested official-sample failure fatal; samples cannot be `off`. |
| `--run-nvbandwidth` | Runs the optional nvbandwidth diagnostic and requires an explicit pinned ref. |
| `--nvbandwidth-path=<path>` | Selects the nvbandwidth source/build path. |
| `--nvbandwidth-ref=<tag-or-commit>` | Pins the nvbandwidth revision; required with `--run-nvbandwidth`. |
| `--install-build-tools` | Permits source-neutral build-tool installation during `apply`. This is the current default. |
| `--no-install-build-tools` | Prohibits build-tool installation; required for a non-installing revalidation workflow. |
| `--help` | Prints runner usage without staging or changing the host. |

P2P testing is opt-in. A passing result records hardware/runtime capability
only; it does not globally enable application P2P, unified memory, or LLM
readiness.

## Fact refresh and ownership

The NVLink playbook first imports the canonical NVIDIA playbook with
`nvidia_mode=validate` and `nvidia_validate_from_facts=true`. That pass reads
the recorded NVIDIA policy, validates the live driver, `nvcc`, and CUDA
runtime header, and refreshes
`/etc/ansible/debian/facts/nvidia.yml` and the canonical shared snapshot at
`/etc/ansible/debian/facts/gpu.yml`. NVLink then rereads both files and fails
closed if schema version, readiness booleans, `CUDA_HOME`, or the NVIDIA
topology-label matrix disagree with the live host.

NVIDIA exclusively owns `nvidia.yml`; the shared GPU layer exclusively owns
`gpu.yml`; NVLink writes only `/etc/ansible/debian/facts/nvlink.yml` after
mandatory GPU, compiler,
per-UUID smoke, and topology gates pass. A schema-1 NVIDIA fact without the
newer `validation_policy` is reconstructed from its legacy recorded fields and
upgraded by the NVIDIA validation pass. Missing, malformed, or unsupported
facts require rerunning the NVIDIA `apply` workflow—do not edit either fact
file by hand.

## Revalidate without installation

After a successful `apply`, rerun the existing managed helpers without package
installation or external sample-source fetching:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- validate \
    --gpu=all \
    --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 \
    --require-nvlink \
    --expect-topology=NV4 \
    --run-p2p-test \
    --strict-p2p \
    --p2p-buffer-mib=256 \
    --p2p-iterations=20 \
    --official-samples=off \
    --no-install-build-tools
```

`validate` can update NVIDIA/NVLink readiness facts, validation logs, and
managed environment metadata. It does not install or upgrade NVIDIA/CUDA
packages. A successful result remains hardware/runtime validation only; it
does not enable global LLM application P2P settings.
