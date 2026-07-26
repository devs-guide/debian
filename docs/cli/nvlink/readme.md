---
title: NVLink validation runner
section: CLI / NVLink
source_path: setup/cli/nvlink.sh
script_url: https://devs-guide.github.io/debian/setup/cli/nvlink.sh
---

# NVLink validation runner

Validates one explicitly resolved pair on a previously installed NVIDIA/CUDA
host. It does not install an NVIDIA driver or CUDA toolkit. Every managed run
first invokes the canonical NVIDIA validator, refreshes NVIDIA-owned readiness
facts and the shared GPU snapshot, and then consumes the current UUID, PCI, and
`GPU#` topology identities.

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Default read-only inventory, compiler, topology, and link-status report. It does not request sudo or write facts. |
| `apply` | Refreshes prerequisite facts, validates NVLink, and optionally installs `build-essential`, builds the directed CUDA P2P helper, and runs it. |
| `validate` | Refreshes prerequisite facts and validates NVLink without installing or compiling. A requested P2P test requires the helper from an earlier `apply`. |

## Privilege model

Use the primary `wget | bash` form:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- preflight --gpu=all
```

For `apply` and `validate`, the runner requests sudo once through `/dev/tty`
when no root, cached, or passwordless credential exists. Password input is not
echoed. Subsequent root commands use noninteractive `sudo -n`; source files
are staged and verified by the invoking user before privileged execution.

`wget | sudo bash` remains supported when the caller deliberately starts the
entire runner as root. Do not use `sudo wget ... | bash`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  sudo bash -s -- validate \
    --gpu=all \
    --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 \
    --require-nvlink \
    --expect-topology=NV4 \
    --no-install-build-tools
```

## Select exactly one pair

Every managed run validates exactly two distinct physical, non-MIG GPUs.

- `--gpu=all` is convenient only when the host exposes exactly two physical
  NVIDIA GPUs.
- `--gpu=GPU-...,GPU-...` or two PCI selectors is the noninteractive form for
  larger hosts and automation.
- `--select-gpus` displays every discovered GPU’s index, name, UUID, PCI ID,
  memory, and compute capability. It requires two distinct choices, restates
  the resolved pair, and asks for confirmation on `/dev/tty` before staging or
  sudo.

Example interactive selection:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- apply \
    --select-gpus \
    --require-exact-gpu-count=2 \
    --require-nvlink \
    --expect-topology=NV4
```

## Core dual-RTX-3090 validation

This complete command proves the shared topology route and live UUID-targeted
NVLink status without requiring a CUDA P2P transfer:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/nvlink.sh | \
  bash -s -- apply \
    --gpu=all \
    --require-exact-gpu-count=2 \
    --require-compute-capability=8.6 \
    --require-nvlink \
    --expect-topology=NV4
```

For an additional strict directed CUDA P2P correctness test:

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
    --install-build-tools
```

## How NVLink readiness is determined

The runner uses two NVIDIA-owned signals:

1. It reads the selected route directly from the canonical shared snapshot’s
   `nvidia-smi topo -m` matrix. An NVLink route matches
   `^NV[1-9][0-9]*$`; an explicitly supplied `--expect-topology` must match
   exactly.
2. It runs `nvidia-smi nvlink -i <UUID> -s` for each selected UUID. Both
   commands must succeed, their output must be recognized, and each GPU must
   expose at least one observed numeric `GB/s` value greater than zero.

`NV4` describes four bonded NVLinks in the topology output. The status check
does not require four output rows and does not compare a reported value with a
model-specific speed. Every `rates_gbps` value is copied from the current
NVIDIA output. There is no hard-coded `14.062`, PCIe-generation inference,
exact-speed requirement, or bandwidth floor other than `rate > 0`.

The optional CUDA P2P helper is separate from core NVLink readiness. Its
measured transfer output is retained, but no PCIe-generation or throughput
threshold is applied. A failed P2P test is fatal only with `--strict-p2p`.

Inspect the same live signals manually:

```bash
nvidia-smi topo -m
nvidia-smi nvlink -i GPU-8444af46-fe12-72b0-c086-17ff75854e8c -s
nvidia-smi nvlink -i GPU-4d8b9b2e-ae12-61ab-bba6-67b01d18a1de -s
```

Replace the example UUIDs with current values from `nvidia-smi -L`.

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--gpu=all\|<UUID-or-PCI-list>` | Selects exactly two physical GPUs. `all` is accepted only when exactly two GPUs are discovered. |
| `--select-gpus` | Interactively chooses and confirms exactly two GPUs on `/dev/tty`; it cannot be combined with `--gpu`. |
| `--require-gpu-count=<minimum>` | Applies the existing minimum-count policy to the resolved pair. |
| `--require-exact-gpu-count=<count>` | Requires the resolved selection to contain this exact count; managed NVLink currently requires two. |
| `--require-compute-capability=<list>` | Requires each selected GPU to match one of the comma-separated `major.minor` capabilities. |
| `--require-nvlink` | Makes a non-NVLink route or missing positive per-GPU link status fatal. It does not require a P2P test. |
| `--expect-topology=NV#` | Requires an exact route such as `NV4`. The token describes bonded links, not pooled VRAM. |
| `--run-p2p-test` | Runs the bounded directed CUDA P2P helper for the selected pair. |
| `--strict-p2p` | Makes a requested P2P failure fatal; it requires `--run-p2p-test`. |
| `--p2p-buffer-mib=<size>` | Sets the test buffer size. The full example uses 256 MiB. |
| `--p2p-iterations=<count>` | Sets the bounded iteration count. The full example uses 20. |
| `--install-build-tools` | Allows `build-essential` installation during `apply` when P2P is requested. |
| `--no-install-build-tools` | Prohibits build-tool installation. |
| `--help` | Prints usage without staging or changing the host. |

P2P testing proves only the requested transfer’s runtime correctness. It does
not globally enable application P2P, unified memory, pooled VRAM, or LLM
readiness.

## Compact fact contract

NVLink writes only `/etc/ansible/debian/facts/nvlink.yml`. Schema version 2
contains the selected identities, route, dynamic status evidence, optional P2P
state, and readiness:

```yaml
nvlink:
  schema_version: 2
  generated_at: "<UTC timestamp>"
  mode: "apply"
  selection:
    source: "auto"
    uuids: ["GPU-...", "GPU-..."]
    pci_bus_ids: ["0000:51:00.0", "0000:8a:00.0"]
    current_indices: [0, 1]
    topology_labels: ["GPU0", "GPU1"]
  topology:
    route: "NV4"
    bonded_count: 4
    expected_route: "NV4"
    route_is_nvlink: true
    expected_route_matches: true
  link_status:
    all_commands_succeeded: true
    all_selected_active: true
    per_gpu:
      - uuid: "GPU-..."
        command_rc: 0
        rates_gbps: ["<observed positive GB/s values>"]
        active: true
        log: "/var/log/nvidia/nvlink/<run>/nvlink-status-GPU-....txt"
  p2p:
    requested: false
    tested: null
    passed: null
    log: null
  readiness:
    nvlink_ready: true
    p2p_ready: null
```

The string inside `rates_gbps` above is a documentation placeholder. The
written fact contains numeric values observed from that host; no example rate
is injected into runtime data. When P2P is not requested, its result and
readiness values are `null`.

NVIDIA owns `/etc/ansible/debian/facts/nvidia.yml`, and the shared GPU runner
owns `/etc/ansible/debian/facts/gpu.yml`. NVLink rereads both files and never
rewrites them. A managed `apply` also removes obsolete NVLink-owned smoke,
topology-wrapper, build-manifest, and environment overlay artifacts; it does
not delete user-managed CUDA Samples or NVBandwidth trees.

## Revalidate without installation

After an `apply` that built the optional P2P helper:

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
    --no-install-build-tools
```

For core-only revalidation, omit all P2P flags. Raw per-UUID status logs and
an optional `p2p.jsonl` are retained in the immutable run directory:

```bash
sudo readlink -f /var/log/nvidia/nvlink/latest
sudo find /var/log/nvidia/nvlink/latest \
  -maxdepth 1 \
  -name 'nvlink-status-GPU-*.txt' \
  -exec sed -n '1,160p' {} \;
sudo sed -n '1,160p' /var/log/nvidia/nvlink/latest/p2p.jsonl
```
