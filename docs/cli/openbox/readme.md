---
title: Openbox runner
section: CLI / Openbox
source_path: setup/cli/openbox.sh
script_url: https://devs-guide.github.io/debian/setup/cli/openbox.sh
---

# Openbox runner

Manages the selected user’s Openbox session integration. Modes are `preflight`,
`apply`, and `disable`.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/openbox.sh | bash
```

The default managed user is `app`. Review `DEBIAN_OPENBOX_*` variables before
changing session commands, X session hooks, or fullscreen behavior.
