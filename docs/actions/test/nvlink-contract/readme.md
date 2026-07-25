---
title: NVLink contract test
section: Actions / Test NVLink contract
source_path: actions/test.nvlink-contract.sh
description: Focused validation of NVLink staging, NVIDIA fact ownership, CUDA helpers, and task ordering.
---

# NVLink contract test

Run the focused NVLink repository contract:

```bash
bash actions/test.nvlink-contract.sh
```

It validates the runner manifest, imported NVIDIA validation order, fact-path
ownership, live prerequisite checks, package groups, audited CUDA helper API
use, YAML, and embedded shell payloads. It does not compile CUDA code, execute
GPU diagnostics, install packages, or alter host facts.

For local review without Python parsing, use:

```bash
bash actions/test.nvlink-contract.sh --shell-only
```
