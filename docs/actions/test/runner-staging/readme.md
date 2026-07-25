---
title: Runner staging contract test
section: Actions / Test runner staging
source_path: actions/test.runner-staging.sh
description: Shell-only regression coverage for shared setup dependency staging.
---

# Runner staging contract test

Run the shell-only shared staging regression from the repository root:

```bash
bash actions/test.runner-staging.sh
```

The action uses isolated temporary directories and mocked downloads. It
checks local and published manifests, nested group-variable/playbook/runtime/
template paths, required manifest declarations, incomplete local checkouts
without a published fallback, missing and empty dependencies, unsafe paths,
duplicate entries, cleanup of partial downloads, and release-helper namespace
isolation.

It does not access the network, call sudo, run Python or Ansible, install
software, or modify generated publication files.
