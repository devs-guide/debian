---
title: NVLink contract test
section: Actions / Test NVLink contract
source_path: actions/test.nvlink-contract.sh
description: Focused validation of lean NVLink staging, ownership, optional P2P, and schema-v2 ordering.
---

# NVLink contract test

Run the focused NVLink repository contract:

```bash
bash actions/test.nvlink-contract.sh
```

It validates the runner manifest, shared lifecycle-helper use, imported NVIDIA
validation order, fact-path ownership, direct shared-topology consumption,
dynamic positive per-UUID rate handling, optional directed CUDA P2P ordering,
the compact schema-version-2 fact, the reduced build package group, YAML, and
embedded shell payloads. It also rejects superseded smoke, topology-wrapper,
CUDA Samples, NVBandwidth, and fixed-rate contracts. It does not compile CUDA
code, execute GPU diagnostics, install packages, or alter host facts.

For local review without Python parsing, use:

```bash
bash actions/test.nvlink-contract.sh --shell-only
```
