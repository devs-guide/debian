# devs-guide/debian

Published Debian bootstrap and host-configuration project.

The public documentation site is [devs-guide.github.io/debian](https://devs-guide.github.io/debian/).
It distinguishes extensionless documentation routes from executable published
source files, which always end in `.sh`.

## Bootstrap

```bash
wget -qO- https://devs-guide.github.io/debian/setup/bootstrap.sh | bash
```

Compatibility entrypoints remain available at `setup/debian.sh` and
`setup/metal.sh`.

## Optional runners

- [CLI runner documentation](https://devs-guide.github.io/debian/cli/)
- [Shared GPU inventory](https://devs-guide.github.io/debian/cli/gpu/)
- [NVIDIA driver and CUDA](https://devs-guide.github.io/debian/cli/nvidia/)
- [NVLink validation](https://devs-guide.github.io/debian/cli/nvlink/)
- [Kiosk workflow](https://devs-guide.github.io/debian/kiosk/)

## Layout

- `docs/`: canonical source for the published documentation site
- `setup/`: published Debian runner source files
- `ansible/`: baseline and feature playbooks, files, and catalogs
- `actions/`: publication and validation tooling
- `static/`: generated Pages output; do not hand-edit
