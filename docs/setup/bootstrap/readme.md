---
title: Bootstrap runner
section: Setup / Bootstrap
source_path: setup/bootstrap.sh
script_url: https://devs-guide.github.io/debian/setup/bootstrap.sh
---

# Bootstrap runner

The primary Debian bootstrap entrypoint resolves the release policy and stages
the baseline Ansible playlist.

## Default baseline

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

## Refresh the cached bootstrap runtime

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | \
  env REFRESH=1 bash
```

| Variable | Purpose |
| --- | --- |
| `REFRESH=1` | Clears the runner’s temporary runtime cache before fetching/staging its current support files. Use when intentionally retrying a changed published runtime. |
| `DEBIAN_RELEASE_GROUP_VARS_FILE` | Optional explicit release overlay. Leave unset for the runner’s Debian release detection unless operating a reviewed alternate release lane. |

The bootstrap playlist is intentionally limited. Optional developer, desktop,
GPU, and kiosk features are installed through their respective runners.
