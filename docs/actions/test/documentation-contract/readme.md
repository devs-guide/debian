---
title: Documentation contract test
section: Actions / Test documentation contract
source_path: actions/test.documentation-contract.sh
description: Shell-only checks for canonical documentation metadata, setup URLs, and Pages action wiring.
---

# Documentation contract test

Run the focused documentation-source contract:

```bash
bash actions/test.documentation-contract.sh
```

It checks shell syntax, canonical `.sh` setup URLs, required documentation
front matter, NVIDIA/NVLink runner-option coverage, positional mode examples,
canonical action-route placement, and the relationship between the
documentation builder, publication manifest, publisher, and Pages validator.
It does not render documentation, access the network, or modify `static/`.
