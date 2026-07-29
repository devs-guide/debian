---
title: Intel Optane ipmctl runner
section: CLI / ipmctl
source_path: setup/cli/ipmctl.sh
script_url: https://devs-guide.github.io/debian/setup/cli/ipmctl.sh
---

# Intel Optane ipmctl runner

`ipmctl.sh` installs one reviewed Intel Optane PMem utility from source,
captures authoritative PMem facts, and separates ordinary installation from
destructive memory-allocation goals.

Debian 13 does not publish an `ipmctl` package. Do not add Bookworm or Sid to a
Trixie host to obtain it. Apply fails if an installed package or configured APT
candidate exposes that cross-release migration. Remove the foreign source
through a separately reviewed package-repository change first. This runner
instead pins the newest upstream 03.x release, which upstream describes as
supporting every Intel Optane PMem generation:

| Source | Reviewed value |
| --- | --- |
| ipmctl repository | `https://github.com/intel/ipmctl.git` |
| ipmctl tag | `v03.00.00.0538` |
| ipmctl commit | `a71f2fb1c90dd07f9862b71c789881132193e8f9` |
| edk2 repository | `https://github.com/tianocore/edk2.git` |
| edk2 tag | `edk2-stable202405` |
| edk2 commit | `3e722403cd16388a0e4044e705a2b34c841d76ca` |
| install prefix | `/usr/local` |

The release includes build-procedure fixes and a PBR parser crash fix. This is
a project-reviewed Debian 13 source build, not upstream Debian 13
certification. The upstream repository is archived, so changing either source
pin requires a new compatibility review.

References:

- [Debian package search](https://packages.debian.org/ipmctl)
- [upstream 03.x README](https://github.com/intel/ipmctl/blob/v03.00.00.0538/README.md)
- [v03.00.00.0538 release](https://github.com/intel/ipmctl/releases/tag/v03.00.00.0538)
- [upstream CMake dependency policy](https://github.com/intel/ipmctl/blob/v03.00.00.0538/CMakeLists.txt)
- [Debian 13 libndctl6](https://packages.debian.org/trixie/libs/libndctl6)
- [ipmctl module output contract](https://docs.pmem.io/ipmctl-user-guide/module-discovery/show-device)
- [ipmctl topology output contract](https://docs.pmem.io/ipmctl-user-guide/module-discovery/show-topology)
- [ipmctl goal safety and syntax](https://docs.pmem.io/ipmctl-user-guide/provisioning/create-memory-allocation-goal)

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Unprivileged read-only report. It does not clone source, install packages, write facts, or change PMem. |
| `apply` | Installs optional build dependencies, builds the reviewed source, installs under `/usr/local`, inventories PMem, and writes facts. It never creates or deletes a goal. |
| `validate` | Runs privileged read-only inventory and refreshes the managed fact. |
| `goal-plan` | Runs all destructive-operation gates and prints the exact proposed goal command without changing PMem. |
| `goal-apply` | Repeats the plan, requires an exact `/dev/tty` confirmation, and creates one whole-capacity goal. |

## Source installation

Start with the read-only report:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- preflight \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=release \
    --no-install-build-tools
```

Build and install the reviewed Release profile:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- apply \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=release \
    --install-build-tools
```

With `--install-build-tools`, the runner authenticates sudo once and installs
only the opt-in `ipmctl_build` package group. It then fetches and verifies both
reviewed Git tags as the invoking user. Source-network access never runs under
sudo.

Then perform privileged read-only validation:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  sudo bash -s -- validate \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=release \
    --no-install-build-tools
```

Release builds use upstream `-Werror`. A compiler warning therefore stops the
build and leaves its evidence in `/var/log/ipmctl/<run>/build.txt`. There is no
automatic fallback. After human review, repeat `apply` with
`--build-type=debug`; Debug disables Release optimization as well as
Release-only `-Werror`, so it is a different managed profile state and build
workspace. A non-current apply replaces only that selected mutable workspace
under `/opt/build/ipmctl`; reviewed source and immutable run logs remain.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- apply \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=debug \
    --no-install-build-tools
```

## Goal workflow

Only whole-capacity profiles are supported:

- `memory-mode` creates `MemoryMode=100`.
- `app-direct` creates `MemoryMode=0 PersistentMemoryType=AppDirect`.
- `app-direct-not-interleaved` creates
  `MemoryMode=0 PersistentMemoryType=AppDirectNotInterleaved`.

Always plan first:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- goal-plan \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=release \
    --goal=memory-mode \
    --socket=all \
    --no-install-build-tools
```

After reviewing the plan, explicitly request the destructive operation:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- goal-apply \
    --profile=trixie-v03.00.00.0538 \
    --repository-url=https://github.com/intel/ipmctl.git \
    --release=v03.00.00.0538 \
    --commit=a71f2fb1c90dd07f9862b71c789881132193e8f9 \
    --edk2-repository-url=https://github.com/tianocore/edk2.git \
    --edk2-release=edk2-stable202405 \
    --edk2-commit=3e722403cd16388a0e4044e705a2b34c841d76ca \
    --build-type=release \
    --goal=memory-mode \
    --socket=all \
    --no-install-build-tools \
    --allow-destructive-goal-change
```

The runner displays a privileged live plan, then requires typing exactly:

```text
I UNDERSTAND PMEM GOAL CHANGES DESTROY DATA AND REQUIRE REBOOT
```

There is no noninteractive bypass. The runner refuses existing namespaces,
pending goals, unsupported modes, partial or unknown socket targets, unhealthy
or unmanageable modules, and locked security state. It does not delete
namespaces, delete PCD, change firmware or security, or reboot.

When the requested whole-capacity mode is already active across every detected
PMem socket and no goal is pending, `goal-apply` is a no-op. It skips the
confirmation and mutation, then performs a read-only validation to refresh the
managed facts.

Creating a goal can destroy App Direct data. Back up and separately
decommission namespaces before goal work. If a command partially fails, do not
repeat it blindly; inspect `/var/log/ipmctl/<run>` and:

```bash
sudo ipmctl show -a -goal
sudo ipmctl show -a -dimm
sudo ipmctl show -a -system -capabilities
sudo ipmctl show -a -region
sudo ndctl list -R
sudo ndctl list -N
```

After a successful non-no-op goal, reboot through the host's normal maintenance
process. The runner never reboots. Then rerun `ipmctl.sh validate` before
refreshing LLM host facts.

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--profile=PROFILE` | Selects one reviewed source/platform profile. |
| `--repository-url=URL` | Exact credential-free ipmctl HTTPS Git URL. |
| `--release=TAG` | Exact reviewed ipmctl tag. |
| `--commit=SHA` | Exact lowercase 40-character ipmctl commit. |
| `--edk2-repository-url=URL` | Exact credential-free edk2 HTTPS Git URL. |
| `--edk2-release=TAG` | Exact reviewed edk2 tag. |
| `--edk2-commit=SHA` | Exact lowercase 40-character edk2 commit. |
| `--build-type=release\|debug` | Chooses an explicitly reviewed build type; no fallback occurs. |
| `--install-build-tools` | Opts `apply` into the `ipmctl_build` package transaction. |
| `--no-install-build-tools` | Forbids package installation. |
| `--goal=MODE` | Selects one supported whole-capacity goal. Goal modes only. |
| `--socket=all\|LIST` | Explicit socket target required by goal modes. In the first implementation, a numeric list must contain every detected PMem socket; partial-socket changes fail closed. |
| `--allow-destructive-goal-change` | Required intent flag for `goal-apply`; it does not bypass `/dev/tty` confirmation. |
| `--help` | Prints help without staging or changing the host. |

## Facts and LLM host order

This runner owns `/etc/ansible/debian/facts/ipmctl.yml`. Immutable command
evidence lives under `/var/log/ipmctl`, and install/goal transaction records
live under `/var/lib/ansible/debian/ipmctl/transactions`.

The `icelake-pmem-dual-3090` LLM host profile requires these facts to show a
live, inventoried, settled Memory Mode configuration. Use this order:

1. `ipmctl.sh apply`
2. idempotent second `ipmctl.sh apply`
3. `ipmctl.sh validate`
4. optional separately accepted `goal-plan` and `goal-apply`
5. maintenance reboot when a goal was created
6. `ipmctl.sh validate`
7. `setup/cli/llm/host.sh validate --require-ipmctl --require-memory-mode`

GitHub Actions verifies source pins, parser fixtures, runner contracts, and the
Debian 13 source build. Hardware discovery and goal acceptance occur only on
the remote PMem host, never on a developer workstation.
