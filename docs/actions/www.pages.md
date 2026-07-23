# `actions/www.pages.sh`

Regenerates the repository's static GitHub Pages tree from the authoritative
source files. It publishes the `.sh` setup entrypoints, the Ansible tree,
documentation, the homepage, and the root README.

Run it from the repository root:

```bash
bash actions/www.pages.sh
```

By default it replaces `static/`. Set `PUBLISH_DIR` (or the legacy
`DIR_PUBLISH`) to generate an alternate output directory:

```bash
PUBLISH_DIR=/tmp/debian-pages bash actions/www.pages.sh
```

Treat `setup/`, `ansible/`, `docs/`, `www/`, and `readme.md` as source. Do not
hand-edit generated files under `static/`.
