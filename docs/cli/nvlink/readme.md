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

## Complete dual-RTX-3090 validation

Run this only after the NVIDIA runner has installed and validated the selected
driver/CUDA policy. It compiles the managed CUDA smoke helper, tests each
selected GPU by UUID, records NVLink topology, and runs the opt-in P2P
diagnostic.

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
    --official-samples=fetch \
    --cuda-samples-tag=v13.1 \
    --install-build-tools
```

| Flag | Purpose in this example |
| --- | --- |
| `--gpu=all` | Selects all NVIDIA GPUs, after which the exact-count and capability gates apply. |
| `--require-exact-gpu-count=2` | Fails unless precisely two selected physical GPUs are present. |
| `--require-compute-capability=8.6` | Requires the RTX 3090 SM 8.6 architecture. |
| `--require-nvlink` / `--expect-topology=NV4` | Fails a PCIe-only or unexpected NVLink topology; `NV4` records four bonded NVLink links. |
| `--run-p2p-test` / `--strict-p2p` | Runs the opt-in directed P2P diagnostic and makes a requested failure fatal. |
| `--p2p-buffer-mib=256` / `--p2p-iterations=20` | Bounds diagnostic transfer memory and repeat count. |
| `--official-samples=fetch` / `--cuda-samples-tag=v13.1` | Fetches the specified CUDA sample revision for optional comparison. |
| `--install-build-tools` | Explicitly permits installation of source-neutral compiler/build dependencies. |

For a later non-mutating recheck, replace `apply` with `validate` and omit
`--install-build-tools` and `--official-samples=fetch`. A successful result is
hardware/runtime validation only; it does not enable global LLM application
P2P settings.
