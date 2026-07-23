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

It verifies required files, shell syntax, setup URL policy, feature markers,
and selected Ansible contracts. It also executes the mocked NVIDIA/NVLink sudo
policy test. It does not install packages, run Ansible, or access GPU hardware.
