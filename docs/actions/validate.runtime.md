# `actions/validate.runtime.sh`

Performs repository-local contract checks before publication. It verifies
required files, shell syntax, source policy markers, published-path rules,
Ansible references, and selected feature contracts.

Run it from the repository root:

```bash
bash actions/validate.runtime.sh
```

The script also runs `test.sudo-access.sh` for the Phase 1 NVIDIA/NVLink
strict-stdin sudo policy. It does not install packages, run Ansible, or access
GPU hardware. Some YAML and embedded-shell validation uses locally available
parsers when present.
