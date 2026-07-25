---
title: Shared setup runner
section: Setup / Shared runner
source_path: setup/runner.common.sh
description: Delegated-root, runtime staging, and dependency-manifest scaffolding for setup entrypoints.
---

# Shared setup runner

`setup/runner.common.sh` is implementation scaffolding for managed setup
entrypoints. It is not a standalone feature and must not be piped directly
into a shell.

The helper provides:

- one-time sudo authentication through `/dev/tty`;
- exact operator confirmations through `/dev/tty` for an explicitly selected,
  high-impact feature action;
- noninteractive delegated-root commands using `sudo -n`;
- unique per-invocation runtime directories;
- path-constrained cleanup;
- one unprivileged HTTP(S) implementation for managed runner-source files;
- local-copy or published-source manifest staging;
- verification that every declared dependency is regular, readable, and
  non-empty before a privileged command consumes it.

## Delegated-root flow

For migrated runners, `wget | bash` is the primary streamed form:

1. The unprivileged shell downloads the feature and its small shared-runner
   bootstrap.
2. Read-only preflight continues without sudo.
3. A managed mode accepts an existing root, cached, or passwordless session.
   Otherwise it runs `sudo -v` exactly once with input from `/dev/tty`.
   A feature can also require an exact typed acknowledgement through that same
   TTY before it permits an explicitly requested high-impact action; there is
   no environment-variable or noninteractive bypass.
4. The original process stages and verifies release helpers, Ansible files,
   and support files.
5. Privileged package and Ansible commands run through noninteractive
   `sudo -n` with a clean explicit environment.

No runner source or managed dependency is downloaded a second time from inside
sudo. `wget | sudo bash` remains supported when a caller deliberately starts
the whole runner as root. `sudo wget | bash` is not equivalent because it
leaves the shell unprivileged.

Without root, cached/passwordless sudo, or a usable `/dev/tty`, managed modes
fail before privileged activity. Noninteractive callers should allocate a TTY
with `ssh -t`, establish a credential first, or use narrowly scoped
passwordless sudo. Interactive feature inputs such as NVLink
`--select-gpus` independently require `/dev/tty`.

## Feature manifest contract

Migrated CLI features declare four source-neutral arrays:

```bash
GROUP_VARS_FILES=("all.yml" "debian.yml")
FEATURE_PLAYBOOKS=("cli/example.yml")
RUNTIME_SUPPORT_REFS=("packages.yml" "files/example/helper")
FEATURE_TEMPLATE_REFS=("templates/example.conf.j2")
```

`runner.stage.ansible.feature` combines these arrays into one verified
manifest. All four arrays are required, even when a category is empty. A
repository checkout copies every dependency into the isolated runtime
directory. A streamed runner downloads the same relative paths from the
published `ansible/` tree. If a local manifest is incomplete, the runner fails
instead of silently mixing local and published revisions.

The initial `runner.common.sh` download is necessarily a small unprivileged
bootstrap performed by the streamed entrypoint. Once loaded, all release
helper, playbook, task, file, and template staging goes through the shared
implementation. Those managed source-file downloads are never performed
inside sudo.

## Migration status

The NVIDIA and NVLink runners use the shared privilege and staging contracts:

- `setup/cli/nvidia.sh`
- `setup/cli/nvlink.sh`

The following legacy runners still contain privileged self-reentry and a
second fetch when started unprivileged from a stream:

- `setup/bootstrap.sh`
- `setup/hardware.sh`
- `setup/autologin.sh`
- `setup/cli/node.sh`
- `setup/cli/codex.sh`
- `setup/cli/kiosk.app.sh`
- `setup/cli/x11.sh`
- `setup/cli/openbox.sh`
- `setup/cli/touchscreen.sh`
- `setup/cli/startx.sh`
- `setup/cli/tauri.sh`

They remain unchanged until each runner has equivalent privilege, argument,
fetch, and staging regression coverage. New managed features should use the
shared API rather than copy a legacy self-reentry implementation.
