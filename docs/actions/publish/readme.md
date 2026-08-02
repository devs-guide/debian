---
title: Publish Pages action
section: Actions / Publish
source_path: actions/www.pages.sh
---

# Publish Pages action

Regenerates the static GitHub Pages tree from the canonical setup, Ansible,
documentation, and repository README sources.

`actions/publication.manifest` is the canonical inventory for source files
and trees. Both this publisher and `actions/validate.pages.sh` consume it.
Every setup entrypoint in the manifest must retain its `.sh` extension;
extensionless executable aliases are rejected.

Manifest entries use three pipe-delimited fields:

```text
file|setup/cli/nvidia.sh|setup/cli/nvidia.sh
tree|ansible|ansible
```

`file` publishes one non-empty regular file. `tree` publishes and validates
every regular file below the declared directory. Unsafe, duplicate,
overlapping, symlinked, or missing entries fail before the output directory is
replaced.

```bash
PUBLISH_DIR=static bash actions/www.pages.sh
```

For an isolated review output, choose a specific temporary directory:

```bash
PUBLISH_DIR=/tmp/debian-pages DOCS_SITE_ROOT=/debian \
  bash actions/www.pages.sh
```

| Variable | Purpose |
| --- | --- |
| `PUBLISH_DIR` | Repository-relative or absolute generated output directory under an existing parent. The action resolves it, rejects broad system/home/repository roots, then removes and recreates this exact directory. |
| `DIR_PUBLISH` | Legacy compatibility alias for `PUBLISH_DIR`. If both are set, this legacy variable currently takes precedence; new automation should use `PUBLISH_DIR`. |
| `DOCS_SITE_ROOT` | Project path embedded in documentation links; `/debian` is the production project-site path. |

The output directory is disposable generated content. Do not hand-edit
`static/`; change its source and rebuild instead.

Pull requests run runtime validation and build this artifact without
deployment. Only a successful push to `main` grants the deploy job write
permission and publishes the previously built artifact to the `www` branch.
