---
title: Build documentation action
section: Actions / Build documentation
source_path: actions/build.docs.sh
---

# Build documentation action

Renders the canonical Markdown hierarchy in `docs/` into an existing static
publish directory.

```bash
bash actions/build.docs.sh \
  --source docs \
  --output static \
  --site-root /debian
```

Pandoc is an explicit prerequisite. The action never installs it; the Pages
workflow supplies it. Canonical pages require `title` and `section` front
matter, and their optional `source_path` must resolve in the checkout.

| Option | Purpose |
| --- | --- |
| `--source docs` | Selects the canonical Markdown source hierarchy. |
| `--output static` | Writes rendered HTML and assets to the selected generated directory. |
| `--site-root /debian` | Generates project-site links for `https://devs-guide.github.io/debian/`. Use the actual project path when validating another Pages site. |

Legacy files retained at the old `docs/` paths are not rendered as current
public pages. They remain in the repository while their content is migrated
into the canonical hierarchy.
