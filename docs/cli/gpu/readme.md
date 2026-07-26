---
title: Shared GPU inventory runner
section: CLI / GPU
source_path: setup/cli/gpu.sh
script_url: https://devs-guide.github.io/debian/setup/cli/gpu.sh
---

# Shared GPU inventory runner

Creates the canonical hardware and runtime snapshot used by GPU-aware
features. It is vendor-neutral at the interface: v1 records PCI
display/accelerator devices for NVIDIA, AMD, and Intel, while NVIDIA gets
additional `nvidia-smi` runtime details such as UUID, compute capability, and
the labels from `nvidia-smi topo -m`.

It never installs a driver, CUDA, packages, kernel modules, repositories, or
boot configuration. Use [NVIDIA](/debian/cli/nvidia/) for the NVIDIA/CUDA
installation policy, then use this runner or [NVLink](/debian/cli/nvlink/) to
refresh and consume the current snapshot.

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Default read-only PCI, NVIDIA runtime, and topology report. No sudo and no facts are written. |
| `apply` | Refreshes `/etc/ansible/debian/facts/gpu.yml`. It requires the managed Ansible controller to already exist. |
| `validate` | Refreshes the same fact. It also requires the managed controller to already exist. |

## Examples

Read the current inventory without changing the host:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/gpu.sh | \
  bash -s -- preflight --vendor=auto
```

Persist the shared snapshot after NVIDIA is installed and live:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/gpu.sh | \
  bash -s -- apply --vendor=auto
```

For managed modes, the runner requests sudo once through `/dev/tty` when no
cached or passwordless credential exists. It stages all files before delegated
root commands and does not fetch a second copy inside sudo. This remains a
supported compatibility form when a caller intentionally starts the entire
runner as root:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/gpu.sh | \
  sudo bash -s -- validate --vendor=nvidia
```

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--vendor=auto\|nvidia` | `auto` records every detected PCI display/accelerator device and adds NVIDIA runtime enrichment when available. `nvidia` limits the persisted device list to NVIDIA devices. |
| `--help` | Prints runner usage without staging or changing the host. |

## Identity contract

The fact at `/etc/ansible/debian/facts/gpu.yml` is the owner-independent,
current-hardware snapshot. It sorts records by canonical PCI address and
records accepted PCI aliases alongside the canonical form.

For NVIDIA devices, three identifiers have different roles:

| Identifier | Correct use |
| --- | --- |
| CUDA UUID | Stable runtime selection for CUDA visibility and UUID-targeted feature diagnostics. |
| PCI address | Physical-device identity, audit evidence, deterministic ordering, and a selector accepted by feature runners. |
| `GPU0` / `GPU1` topology label | The local label used only to index the matrix in the same `nvidia-smi topo -m` capture. It is not a stable CUDA ordinal. |

NVLink resolves a requested UUID or PCI selector against this snapshot and
uses the selected records' current topology labels to read the shared matrix
directly. This avoids treating a selected-list position or CUDA index as a
topology-table identity.

The snapshot records a `label_mapping` result beside the raw topology matrix.
NVLink proceeds only when every NVIDIA runtime row maps to a current `GPU#`
header and route-row label from that same capture. When a working NVIDIA
runtime produces an incomplete mapping, the GPU runner fails before replacing
an existing `/etc/ansible/debian/facts/gpu.yml`. Repeating the same command
cannot repair deterministic malformed input or parser behavior.

Inspect the raw topology without losing invisible characters:

```bash
nvidia-smi topo -m | sed -n 'l'
nvidia-smi topo -m | od -An -tx1c
sudo sed -n '/nvidia_smi:/,/runtime:/p' /etc/ansible/debian/facts/gpu.yml
```

Do not substitute UUIDs, PCI addresses, CUDA indices, or selected-list
positions for topology labels.

AMD and Intel support in v1 is PCI discovery only. This runner does not claim
vendor runtime readiness, topology capability, or compute validation for them.
