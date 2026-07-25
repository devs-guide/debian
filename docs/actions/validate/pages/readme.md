---
title: Pages validation action
section: Actions / Validate Pages
source_path: actions/validate.pages.sh
---

# Pages validation action

Fetches the published Pages artifacts and compares them with the local source
or locally rendered output.

Source paths come from `actions/publication.manifest`. Documentation routes
are discovered from the complete local render, so adding a canonical
`docs/**/readme.md` page does not require another hard-coded validation list.

```bash
bash actions/validate.pages.sh
```

The default target is `https://devs-guide.github.io/debian`. Override it with
`BASE_URL` after a deployment to another project site. This action requires
network access, `curl`, and Pandoc because it renders the canonical local
documentation before comparing public routes.

```bash
BASE_URL=https://example.invalid/debian \
  bash actions/validate.pages.sh
```

| Variable | Purpose |
| --- | --- |
| `BASE_URL` | Published project URL to fetch and compare. It must include the project path, such as `/debian`. |
