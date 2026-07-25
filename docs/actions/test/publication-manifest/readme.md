---
title: Publication manifest test
section: Actions / Test publication manifest
source_path: actions/test.publication-manifest.sh
description: Shell-only regression coverage for canonical Pages source publication entries.
---

# Publication manifest test

Run the shell-only manifest regression:

```bash
bash actions/test.publication-manifest.sh
```

It validates `actions/publication.manifest`, confirms every setup runner has
one canonical `.sh` destination, and exercises rejection of unsafe paths,
extensionless setup destinations, missing sources, and duplicate
destinations.

The test uses an isolated temporary directory and does not publish files or
access the network.
