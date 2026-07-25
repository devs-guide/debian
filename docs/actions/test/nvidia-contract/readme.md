---
title: NVIDIA contract test
section: Actions / Test NVIDIA contract
source_path: actions/test.nvidia-contract.sh
description: Focused validation of the NVIDIA runner, playbook, fact schema, and skipped-register regression.
---

# NVIDIA contract test

Run the complete NVIDIA repository contract in the CI validation environment:

```bash
bash actions/test.nvidia-contract.sh
```

The action checks stable runner variables, manifest relationships, Ansible
task ordering, CUDA environment policy, fact fields, and the prohibited
skipped-register dereference. It also executes
`actions/test.nvidia-facts.sh`, which requires the pinned Ansible and PyYAML
versions from `actions/requirements.validation.txt`.

It does not install NVIDIA packages or access GPU hardware.

For local review without Python or Ansible execution, run only the portable
shell assertions:

```bash
bash actions/test.nvidia-contract.sh --shell-only
```
