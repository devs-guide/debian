---
title: Metal compatibility entrypoint
section: Setup / Metal
source_path: setup/metal.sh
script_url: https://devs-guide.github.io/debian/setup/metal.sh
---

# Metal compatibility entrypoint

`setup/metal.sh` remains a published compatibility entrypoint for the baseline
bootstrap flow.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/metal.sh | bash
```

It is a compatibility entrypoint for the baseline bootstrap behavior, not a
hardware/GPU installer. Use the Hardware or NVIDIA documentation for those
separate policies.

For current instructions, use the [bootstrap runner](/debian/setup/bootstrap/)
documentation.
