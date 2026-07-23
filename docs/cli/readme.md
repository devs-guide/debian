---
title: CLI runners
section: CLI
source_path: setup/cli
description: Opt-in Debian feature runners published as shell source files.
---

# CLI runners

Each path below is documentation. The matching executable is the `.sh` URL
shown on that page. Do not substitute an extensionless documentation path into
a shell pipeline.

## Feature runners

- [Codex](/debian/cli/codex/) — Node and Codex CLI setup.
- [Kiosk app](/debian/cli/kiosk.app/) — kiosk feature orchestration.
- [Node](/debian/cli/node/) — Node LTS setup.
- [NVIDIA](/debian/cli/nvidia/) — opt-in NVIDIA driver and CUDA readiness.
- [NVLink](/debian/cli/nvlink/) — opt-in CUDA/NVLink validation after NVIDIA.
- [Openbox](/debian/cli/openbox/) — Openbox session configuration.
- [STARTX](/debian/cli/startx/) — local console X startup wiring.
- [Tauri](/debian/cli/tauri/) — Tauri runtime/build dependencies.
- [Touchscreen](/debian/cli/touchscreen/) — touchscreen configuration.
- [X11](/debian/cli/x11/) — minimal X11 prerequisites.

Most runners support a local file invocation as well as the published source
URL. Use the local form when iterating on a checkout.
