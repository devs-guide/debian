---
title: Repository actions
section: Actions
source_path: actions
---

# Repository actions

Run action scripts from the repository root. The documentation build is part
of the Pages publication contract; it never installs its renderer.

## Full CI contract

```bash
bash actions/validate.runtime.sh
```

The full orchestrator expects the pinned validation environment and executes
the Ansible NVIDIA fact fixture. For a shell-only local review, run:

```bash
bash actions/test.documentation-contract.sh
bash actions/test.publication-manifest.sh
bash actions/test.runner-contract.sh
bash actions/test.nvidia-contract.sh --shell-only
bash actions/test.nvlink-contract.sh --shell-only
```

These checks have no install or deployment side effect. Rendering/publishing
commands are documented separately because they intentionally write a
selected output directory.

- [Build documentation](/debian/actions/build-docs/)
- [Publish Pages tree](/debian/actions/publish/)
- [Validate runtime](/debian/actions/validate/runtime/)
- [Validate Pages](/debian/actions/validate/pages/)
- [Action validation libraries](/debian/actions/library/)
- [Test documentation contract](/debian/actions/test/documentation-contract/)
- [Test publication manifest](/debian/actions/test/publication-manifest/)
- [Test shared runner contract](/debian/actions/test/runner-contract/)
- [Test sudo access policy](/debian/actions/test/sudo-access/)
- [Test runner staging](/debian/actions/test/runner-staging/)
- [Test NVIDIA contract](/debian/actions/test/nvidia-contract/)
- [Test NVIDIA facts](/debian/actions/test/nvidia-facts/)
- [Test NVLink contract](/debian/actions/test/nvlink-contract/)

`www.pages.sh` replaces its selected publish directory. Validation scripts
only read project content, aside from temporary download/build locations.
