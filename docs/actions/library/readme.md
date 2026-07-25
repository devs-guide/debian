---
title: Action validation libraries
section: Actions / Library
source_path: actions/lib
description: Shared portable assertions, YAML checks, and publication-manifest parsing for repository actions.
---

# Action validation libraries

The files under `actions/lib/` are sourced implementation helpers, not
standalone commands:

- `contracts.sh` provides portable `rg`/`grep` searching, common assertions,
  shell syntax checks, YAML parsing, and embedded-shell validation.
- `publication.sh` validates and iterates the canonical publication manifest
  without evaluating manifest content as shell code.

Focused test actions and the public validation orchestrators use these
libraries so error handling and fallback behavior remain consistent.
