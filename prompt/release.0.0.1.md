## 0.0.1

Published the first minimal Debian bootstrap release for the new Debian-first
runtime and publish workflow.

This release establishes the smallest end-to-end bootstrap surface that is
useful in production: published setup entrypoints, release-aware controller
Python and Ansible resolution, a minimal baseline playbook set, and default
access policy that keeps the host reachable and manageable after first boot.
It does not try to ship the full Debian opinionation layer yet. The goal of
`0.0.1` is a narrow, reliable bootstrap that is easy to reason about and easy
to extend in later releases.

### Scope

- Release range: repo init..HEAD
- Target lane: Debian minimal bootstrap workflow
- Primary published runner: `setup/bootstrap.sh`
- Compatibility aliases:
  - `setup/debian.sh`
  - `setup/metal.sh`
- Baseline playlist:
  - `ansible/bootstrap.yml`
  - `ansible/sources.yml`
  - `ansible/install.packages.yml`
  - `ansible/users.yml`
  - `ansible/security.yml`
  - `ansible/sysctl.yml`
  - `ansible/lan.yml`
  - `ansible/network.yml`
  - `ansible/logging.yml`
- Core runtime files:
  - `setup/release.common.sh`
  - `ansible/group_vars/all.yml`
  - `ansible/group_vars/trixie.yml`
  - `ansible/group_vars/buster.yml`
  - `actions/www.pages.sh`
  - `actions/validate.runtime.sh`

### Highlights

- Replaced the repo runtime identity with a Debian-first bootstrap and publish
  layout.
- Published a stable GitHub Pages entrypoint for bootstrap consumption and
  aligned the repo around `setup/` and `ansible/` as the active runtime paths.
- Made controller runtime selection release-aware so modern Debian hosts reuse
  compatible system Python while older lanes can fall back to a managed build.
- Reduced the bootstrap scope to the minimal baseline required to configure the
  host and keep operator access intact after bootstrap.
- Hardened default access behavior around managed users, SSH policy, UFW rules,
  and runtime validation so bootstrap fails loudly when the access contract is
  broken.

### Added

- Debian-first published bootstrap entrypoints under `setup/`.
- Shared bootstrap helper logic in `setup/release.common.sh`.
- Release overlays and controller-runtime policy in `ansible/group_vars/`.
- Minimal baseline playbooks for packages, users, security, sysctl, LAN,
  network, and logging.
- Runtime and Pages validation scripts for publish and bootstrap integrity.
- Prompt-local planning and release workflow files for Debian maintenance.

### Changed

- Moved the repo away from Proxmox-specific runtime structure and into a Debian
  runtime namespace.
- Standardized published paths so setup assets read left to right for operator
  discovery, including `debian/setup/bootstrap.sh` and `debian/setup/cli/codex.sh`.
- Switched bootstrap temp/runtime paths to neutral `/tmp/ansible/debian`
  locations instead of product-branded cache paths on the target host.
- Narrowed the default bootstrap playlist to a minimal operator-safe baseline
  instead of trying to provision the broader feature stack in the first cut.
- Wired GitHub Pages publication around generated `static/` output so public
  bootstrap files are rebuilt on mainline changes.

### Fixed

- Fixed repeated controller-Python build attempts on hosts that already ship a
  compatible system Python.
- Fixed managed Ansible venv reuse checks so stale or invalid controller
  runtimes are not silently reused.
- Fixed bootstrap refresh behavior so `REFRESH=1` invalidates cached runtime
  files cleanly.
- Fixed default-user password refresh and sudo membership behavior for the
  bootstrap-managed `root`, `agent`, and `app` accounts.
- Fixed SSH and UFW bootstrap policy ordering so SSH is validated before
  firewall enablement and baseline LAN access is asserted at runtime.
- Fixed skipped-loop result handling in `ansible/users.yml` so the sudo
  assertion does not crash on the skipped `root` verification path.

### #COMMIT

`release:0.0.1 - add minimal bootstrap release notes`

### Commits since repo init

- `init:ansible: bootstrap workflow for - users, ssh, lan`
- `fix:github: actions setup`
- `fix:github:actions - not published`
- `fix:debian:bootstrap: skip python builds when system>=3.12`
- `fix:debian:bootstrap: skip python builds when system>=3.12`
- `fix:ansible:debian:bootstarp: force refresh by param \`REFRESH=1\``
- `fix:ansible:bootstrap: do not build python3>=3.12`
- `fix:ansible:bootstrap: do not build python3>=3.12`
- `fix:ansible:bootstrap:python - venv missing in logic load order`
- `fix:ansible:python - not using correct venv`
- `fix:ansible:bootstrap: enforce py312 contract and venv capability`
- `fix:ansible:bootstrap: make controller python release-aware`
- `fix:ansible:bootstrap: hardening playlist after controller setup`
- `fix:ansible:bootstrap: ssh networking`
- `fix:ansible:bootstarp: ssh, ufw, default users access`
- `fix:ansible:bootstrap: ssh users sudo permissions`

### Assets

- `prompt/release.0.0.1.md` as the GitHub release notes attachment/body source
- No additional binary artifacts
