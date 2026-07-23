---
title: Bootstrap runner
section: Setup / Bootstrap
source_path: setup/bootstrap.sh
script_url: https://devs-guide.github.io/debian/setup/bootstrap.sh
---

# Bootstrap runner

The primary Debian bootstrap entrypoint resolves the release policy and stages
the baseline Ansible playlist.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

The bootstrap playlist is intentionally limited. Optional developer, desktop,
GPU, and kiosk features are installed through their respective runners.
