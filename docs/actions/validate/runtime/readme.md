---
title: Runtime validation action
section: Actions / Validate runtime
source_path: actions/validate.runtime.sh
---

# Runtime validation action

Checks repository-local runtime contracts before publication.

```bash
bash actions/validate.runtime.sh
```

It remains the public orchestrator for focused documentation, publication,
shared-runner, NVIDIA, and NVLink contract actions, followed by the legacy
runtime checks that have not yet been extracted.

This action has no supported flags. CI provides pinned Ansible and PyYAML
dependencies for real YAML parsing and the skipped-register NVIDIA fact
fixture. Locally, use the focused `--shell-only` NVIDIA/NVLink actions listed
on the [Actions index](/debian/actions/) when Python and Ansible execution is
not appropriate.

The orchestrator does not install packages, execute host playbooks, compile
CUDA code, or access GPU hardware.
