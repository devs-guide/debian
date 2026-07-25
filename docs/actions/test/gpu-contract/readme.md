---
title: GPU contract test action
section: Actions / Test / GPU contract
source_path: actions/test.gpu-contract.sh
---

# GPU contract test action

Runs focused static and fixture-backed checks for the shared GPU inventory
layer.

```bash
bash actions/test.gpu-contract.sh
```

`--shell-only` validates runner/source contracts without executing the Python
topology fixture. CI runs the full form, which checks that the exact captured
`GPU0`/`GPU1` `nvidia-smi topo -m` table resolves the `NV4` route even when
the GPU columns are reordered, and that an unknown topology label fails
closed.

```bash
bash actions/test.gpu-contract.sh --shell-only
```

The action verifies that `gpu.yml` is owned by the shared inventory task, that
NVIDIA topology uses labels rather than CUDA indices, and that the generic
runner stages every required support file.
