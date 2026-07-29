---
title: Shared LLM host-readiness runner
section: CLI / LLM / Host
source_path: setup/cli/llm/host.sh
script_url: https://devs-guide.github.io/debian/setup/cli/llm/host.sh
---

# Shared LLM host-readiness runner

`host.sh` creates the machine-level contract consumed by later LLM features.
It inventories CPU topology, chooses one logical CPU per physical core, records
NUMA and memory capacity, classifies available persistent-memory evidence, and
checks producer-owned GPU facts when requested.

This is scaffolding, not an inference runtime. It does not install
KTransformers, download a model, disable swap, modify `sysctl`, select a CPU
governor, alter the kernel or bootloader, or rewrite NVIDIA policy.

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Default read-only report. It reads current host observations and GPU facts without sudo or persistent changes. |
| `apply` | Validates policy, optionally installs the explicit support package group, creates only missing managed directories, and writes the host contract. |
| `validate` | Revalidates and refreshes the contract without bootstrapping Ansible or installing packages. |

## Safe first run

Review the current host and producer facts:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- preflight \
    --profile=generic \
    --owner=gpt \
    --group=gpt
```

Create a generic host contract without installing support packages:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- apply \
    --profile=generic \
    --owner=gpt \
    --group=gpt \
    --host-reserve-gib=96 \
    --gpu-reserve-mib=4096 \
    --require-physical-cores=4 \
    --no-install-support-packages
```

The reviewed Ice Lake PMem, dual RTX 3090, CUDA 13.1, NV4, and directed-P2P
profile is stricter:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- apply \
    --profile=icelake-pmem-dual-3090 \
    --owner=gpt \
    --group=gpt \
    --host-reserve-gib=96 \
    --gpu-reserve-mib=4096 \
    --require-physical-cores=36 \
    --require-memory-mode \
    --require-ipmctl \
    --require-nvidia \
    --require-nvlink \
    --require-p2p \
    --install-support-packages
```

The runner requests sudo once through `/dev/tty` for managed modes. It stages
the runner dependencies before delegated-root execution. An explicit
whole-runner root invocation remains supported:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  sudo bash -s -- validate \
    --profile=generic \
    --owner=gpt \
    --group=gpt \
    --no-install-support-packages
```

For a checked-out repository, use the same modes and flags directly:

```bash
./setup/cli/llm/host.sh preflight \
  --profile=generic \
  --owner="$(id -un)" \
  --group="$(id -gn)"
```

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--profile=generic\|icelake-pmem-dual-3090` | Selects the generic policy or the reviewed exact-host profile. |
| `--owner=USER` | Non-root account that must be able to write the managed LLM paths. Defaults to the invoking account or `SUDO_USER`. |
| `--group=GROUP` | Managed group. Defaults to the owner's primary group. |
| `--host-reserve-gib=N` | RAM that later capacity planners must leave for the OS and non-model work. Default: 96 GiB. |
| `--allow-low-host-reserve` | Permits validation while current `MemAvailable` is below the requested reserve. Use only after reviewing active workloads. |
| `--gpu-reserve-mib=N` | Per-device VRAM reservation exported for later runtimes. It does not allocate or test VRAM. Default: 4096 MiB. |
| `--require-physical-cores=N` | Requires at least N physical cores and records one logical CPU from each core. |
| `--require-memory-mode` | Requires `verified` ipmctl evidence or `consistent` DMI persistent-memory evidence. Unknown evidence fails closed. |
| `--require-ipmctl` | Requires current schema-1 `/etc/ansible/debian/facts/ipmctl.yml`, a matching live binary, complete inventory, and matching fact/live evidence that no PMem goal is pending. |
| `--require-nvidia` | Requires schema-1 GPU/NVIDIA facts and matching live UUIDs, loaded driver, `nvidia-smi`, `nvcc`, and CUDA runtime headers. |
| `--require-nvlink` | Also requires a current schema-2 NVLink fact with a physical pair, NVLink route, and positive link evidence. Requires `--require-nvidia`. |
| `--require-p2p` | Also requires a completed passing directed CUDA P2P result. Requires `--require-nvlink`. |
| `--install-support-packages` | On `apply`, installs only the opt-in `llm_host_support` package group. |
| `--no-install-support-packages` | Skips the optional package transaction. This is the default. |
| `--help` | Prints usage without staging or changing the host. |

Flag dependencies fail before staging or sudo:

- `--require-p2p` requires `--require-nvlink`.
- `--require-nvlink` requires `--require-nvidia`.
- `--profile=icelake-pmem-dual-3090` enables the Memory Mode, ipmctl, NVIDIA,
  NVLink, P2P, and 36-physical-core requirements even when the equivalent
  flags are omitted.

## Recommended remote acceptance sequence

After publishing the runner, execute these steps on the target host in order.
Keep the policy values identical across all managed runs.

1. Capture a read-only report:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- preflight \
    --profile=icelake-pmem-dual-3090 \
    --owner=gpt \
    --group=gpt \
    --host-reserve-gib=96 \
    --gpu-reserve-mib=4096 \
    --require-physical-cores=36 \
    --require-memory-mode \
    --require-ipmctl \
    --require-nvidia \
    --require-nvlink \
    --require-p2p \
    --no-install-support-packages
```

2. Apply the contract and install only the optional host support group:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- apply \
    --profile=icelake-pmem-dual-3090 \
    --owner=gpt \
    --group=gpt \
    --host-reserve-gib=96 \
    --gpu-reserve-mib=4096 \
    --require-physical-cores=36 \
    --require-memory-mode \
    --require-ipmctl \
    --require-nvidia \
    --require-nvlink \
    --require-p2p \
    --install-support-packages
```

3. Run the same `apply` command again. The second run is the idempotency
   check: no existing directory ownership or modes should be rewritten, and
   already-installed packages should remain unchanged.

4. Validate without allowing a package transaction:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/host.sh | \
  bash -s -- validate \
    --profile=icelake-pmem-dual-3090 \
    --owner=gpt \
    --group=gpt \
    --host-reserve-gib=96 \
    --gpu-reserve-mib=4096 \
    --require-physical-cores=36 \
    --require-memory-mode \
    --require-ipmctl \
    --require-nvidia \
    --require-nvlink \
    --require-p2p \
    --no-install-support-packages
```

5. Review the persisted result and managed inspection helpers:

```bash
sudo sed -n '1,320p' /etc/ansible/debian/facts/llm-host.yml
/opt/llm/bin/llm-host-status
/opt/llm/bin/llm-host-capacity
/opt/llm/bin/llm-host-numa
/opt/llm/bin/llm-host-env
```

Acceptance requires `readiness.host_ready: true`, matching current GPU UUIDs,
the expected CPU/NUMA and Memory Mode evidence, and no unexpected ownership
or mode changes under `/opt/llm` or `/models`.

## Facts and ownership

The runner writes:

- `/etc/ansible/debian/facts/llm-host.yml` — schema-version-1 host contract.
- `/etc/ansible/debian/env/llm-host.sh` — source-neutral environment values.
- `/opt/llm/bin/llm-host-status`
- `/opt/llm/bin/llm-host-capacity`
- `/opt/llm/bin/llm-host-numa`
- `/opt/llm/bin/llm-host-env`

It consumes but never owns:

- `/etc/ansible/debian/facts/ipmctl.yml`
- `/etc/ansible/debian/facts/gpu.yml`
- `/etc/ansible/debian/facts/nvidia.yml`
- `/etc/ansible/debian/facts/nvlink.yml`

If a PMem goal, driver, CUDA toolkit, kernel, GPU, NVLink bridge, or GPU
ordering changes, refresh those producers before rerunning host validation.
After a PMem goal and maintenance reboot, run `ipmctl.sh validate` first. The
host gate rejects pending PMem goals and stale producer identity.

Managed paths include `/opt/src`, `/opt/venvs`, `/opt/llm`, and the `/models`
subtree. Missing directories are created for the selected owner. Existing
directories retain their owner and mode; they must already be real,
non-symlink directories writable by that owner. There is no recursive
ownership repair.

## Memory Mode classification

`verified` means live inventory reported positive Memory Mode capacity.
`consistent` means DMI records provide persistent-memory evidence but the
stronger query is unavailable. `unknown` makes no claim. The generic profile
can record `unknown`; `--require-memory-mode` rejects it. The exact Ice Lake
profile also requires source-managed ipmctl facts with positive PMem volatile
capacity, DDR cache capacity, and no pending goal.

PCIe or NVLink bandwidth is not hard-coded here. Link-rate evidence remains
owned by the NVLink producer and is treated as positive/active evidence rather
than a fixed throughput threshold.

## Next implementation

After remote preflight, first apply, idempotent second apply, and validate are
accepted, run `setup/cli/llm/llamacpp.sh` with one reviewed repository/tag/full
commit tuple. Accept its model-free build and one local-GGUF smoke before
running `setup/cli/llm/ktransformers.sh`. KTransformers remains independently
owned and does not consume the llama.cpp runtime. Model acquisition and the
first 80 GB MoE smoke remain later acceptance gates.
