---
title: NVIDIA fact normalization test
section: Actions / Test NVIDIA facts
source_path: actions/test.nvidia-facts.sh
description: CI regression for skipped Ansible register shapes and schema-1 NVIDIA facts.
---

# NVIDIA fact normalization test

This CI action executes the shared NVIDIA observation-normalization task
against skipped Ansible registered-result dictionaries:

```bash
bash actions/test.nvidia-facts.sh
```

It requires the exact packages in `actions/requirements.validation.txt`.
The fixture verifies persisted candidate fallback behavior, empty fallback
behavior, integer return codes, and a parseable schema-version-1 NVIDIA fact
document.

The repository workflow installs those pinned validation dependencies before
calling runtime validation. The action does not install dependencies itself.
