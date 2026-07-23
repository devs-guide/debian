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

The output directory is disposable generated content. Do not hand-edit
`static/`; change its source and rebuild instead.
