---
title: LLM host contract test action
section: Actions / Test / LLM host contract
source_path: actions/test.llm-host-contract.sh
---

# LLM host contract test action

Runs focused safety, runner-staging, playbook, documentation, and fixture
checks for the shared LLM host-readiness layer:

```bash
bash actions/test.llm-host-contract.sh
```

The fixture verifies deterministic one-thread-per-physical-core selection,
the resulting CPU list and mask, NUMA memory and distance parsing, available
memory, and positive Memory Mode classification.

For a source-only review that defers Python fixture execution:

```bash
bash actions/test.llm-host-contract.sh --shell-only
```

The action also rejects model/runtime installation and kernel, swap, sysctl,
governor, bootloader, or recursive-ownership mutations from Phase 1.
