---
title: Repository actions
section: Actions
source_path: actions
---

# Repository actions

Run action scripts from the repository root. The documentation build is part
of the Pages publication contract; it never installs its renderer.

## Local contract check

```bash
bash actions/validate.runtime.sh
```

This has no install or deployment side effect. Rendering/publishing commands
are documented separately because they intentionally write a selected output
directory.

- [Build documentation](/debian/actions/build-docs/)
- [Publish Pages tree](/debian/actions/publish/)
- [Validate runtime](/debian/actions/validate/runtime/)
- [Validate Pages](/debian/actions/validate/pages/)
- [Test sudo access policy](/debian/actions/test/sudo-access/)

`www.pages.sh` replaces its selected publish directory. Validation scripts
only read project content, aside from temporary download/build locations.
