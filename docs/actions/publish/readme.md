---
title: Publish Pages action
section: Actions / Publish
source_path: actions/www.pages.sh
---

# Publish Pages action

Regenerates the static GitHub Pages tree from the canonical setup, Ansible,
documentation, and repository README sources.

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
| `PUBLISH_DIR` | Generated static output directory. The action removes and recreates this exact directory. |
| `DOCS_SITE_ROOT` | Project path embedded in documentation links; `/debian` is the production project-site path. |

The output directory is disposable generated content. Do not hand-edit
`static/`; change its source and rebuild instead.
