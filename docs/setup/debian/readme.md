---
title: Debian compatibility entrypoint
section: Setup / Debian
source_path: setup/debian.sh
script_url: https://devs-guide.github.io/debian/setup/debian.sh
---

# Debian compatibility entrypoint

`setup/debian.sh` remains a published compatibility entrypoint for the
baseline bootstrap flow.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/debian.sh | bash
```

It accepts the same baseline behavior as `bootstrap.sh`; it is retained for
compatibility rather than as a separate feature policy. Use the bootstrap page
for cache-refresh and release-overlay controls.

For new documentation and examples, prefer the primary
[bootstrap runner](/debian/setup/bootstrap/).
