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
shared-runner, GPU, ipmctl, LLM-host, NVIDIA, and NVLink contract actions,
followed by the legacy runtime checks that have not yet been extracted.

This action has no supported flags. CI provides pinned Ansible and PyYAML
dependencies for real YAML parsing and the fixture-backed fact contracts.
Locally, use the focused `--shell-only` actions listed on the
[Actions index](/debian/actions/) when Python and Ansible execution is not
appropriate. Reviewed ipmctl source compilation runs in its separate Debian
13 GitHub Actions job.

The orchestrator does not install host packages, execute host playbooks,
compile CUDA code, reconfigure PMem, or access GPU/PMem hardware.
