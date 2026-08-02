---
title: Intel Optane ipmctl runner
section: CLI / ipmctl
source_path: setup/cli/ipmctl.sh
script_url: https://devs-guide.github.io/debian/setup/cli/ipmctl.sh
---

# Intel Optane ipmctl runner

`ipmctl.sh` installs one reviewed Intel Optane PMem CLI build on Debian 13
amd64 and provides a small read-only verification mode. Debian Trixie does not
publish an `ipmctl` binary package, so the runner builds from exact upstream
source instead of mixing packages from another Debian release. Intel archived
ipmctl and does not promise further fixes or releases, so this repository owns
and discloses its finite downstream build policy.

The runner does not create or delete PMem goals, format DIMMs, manage
namespaces, change firmware or security state, or reboot the host. The
installed `ipmctl` program remains an administrative tool, so any command not
shown here is outside this automation and requires separate human review.

## Reviewed source tuple

| Source | Reviewed value |
| --- | --- |
| ipmctl repository | `https://github.com/intel/ipmctl.git` |
| ipmctl tag | `v03.00.00.0538` |
| ipmctl commit | `a71f2fb1c90dd07f9862b71c789881132193e8f9` |
| expected version | `03.00.00.0538` |
| EDK2 repository | `https://github.com/tianocore/edk2.git` |
| EDK2 tag | `edk2-stable202511` |
| EDK2 commit | `46548b1adac82211d8d11da12dd914f41e7aa775` |
| install prefix | `/usr/local` |

Three repository-owned, checksum-pinned compatibility patches are applied:

1. An exact EDK2 `MdePkg/Include/Base.h` host-build patch regenerated against
   the pinned CRLF source blob.
2. The meta-intel patch that removes Release `-Werror` from the C compiler
   flags for this archived source.
3. The meta-intel patch that removes PIE from shared-library linker flags.

Every patch is checked for its file checksum, sole target, exact preimage,
strict applicability, reverse applicability, exact postimage, and clean Git
diff before compilation. This replaces Intel's drifting `patch_OS.sh` and
`updateedk.sh` path with a small reproducible patch pack.

References:

- [Intel ipmctl v03.00.00.0538](https://github.com/intel/ipmctl/releases/tag/v03.00.00.0538)
- [Intel Linux build issue 199](https://github.com/intel/ipmctl/issues/199)
- [meta-intel ipmctl recipe](https://github.com/YoeDistro/meta-intel/tree/8877caca6b1fe6efe33c756698ce6ecdcaea2238/dynamic-layers/openembedded-layer/recipes-support/ipmctl/ipmctl)
- [EDK2 stable202511](https://github.com/tianocore/edk2/releases/tag/edk2-stable202511)
- [Debian package search for ipmctl](https://packages.debian.org/search?keywords=ipmctl)

## Install

Run as the non-root account that should own the source cache. The runner asks
for sudo through `/dev/tty`, installs only the opt-in `ipmctl_build` dependency
group, builds as the invoking user, and installs into `/usr/local` as root.

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  bash -s -- install
```

For an audit-friendly remote run, download and review the exact published
entrypoint first:

```bash
wget -qO /tmp/devs-guide-ipmctl.sh \
  https://devs-guide.github.io/debian/setup/cli/ipmctl.sh
less /tmp/devs-guide-ipmctl.sh
bash /tmp/devs-guide-ipmctl.sh install
```

The exact Git tags and commits are verified before patches are applied. CMake
uses a Release build with two parallel jobs. A successful install records its
commits, patch checksums, toolchain, binary checksum, and install manifest at:

```text
/var/lib/devs-guide/ipmctl/receipt.json
```

A repeat install skips source fetching and compilation only when the receipt,
binary checksum, exact version, and complete runtime linkage still match.
The installer refuses to overwrite an unmanaged `/usr/local/bin/ipmctl`.
Failed build workspaces remain under the invoking user's
`~/.cache/devs-guide/ipmctl/runs/` for inspection.

## Verify

Verification does not bootstrap Ansible or install packages. It requires the
exact `/usr/local/bin/ipmctl` version and no unresolved `ldd` dependencies,
then runs four privileged read-only probes:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/ipmctl.sh | \
  sudo bash -s -- verify
```

The probes are equivalent to:

```bash
sudo /usr/local/bin/ipmctl show -a -dimm
sudo /usr/local/bin/ipmctl show -topology
sudo /usr/local/bin/ipmctl show -memoryresources
sudo /usr/local/bin/ipmctl show -a -goal
```

Output is printed in labeled sections for a human to review. A hardware probe
failure is a warning distinct from a broken software installation.

| Exit | Meaning |
| --- | --- |
| `0` | Software and all requested read-only probes passed. |
| `1` | Binary version, linkage, or another software check failed. |
| `2` | Software passed, but at least one hardware probe needs review. |
| `3` | Platform, privilege, staging, or another prerequisite blocked the run. |
| `64` | Invalid mode or option. |

Only `install`, `verify`, and `--help` are accepted. PMem allocation changes
remain a manual maintenance operation outside this runner.

## Remote acceptance

Before merge, fetch the candidate commit into the intended Debian 13 amd64
PMem-200 server and run from that checked-out repository. Do not substitute an
unpublished Pages URL for the reviewed candidate files.

1. Capture `/etc/os-release`, architecture, kernel, GCC/G++, CMake, Python, and
   the installed build-dependency versions for the pull-request evidence.
2. Run `bash setup/cli/ipmctl.sh install` once and retain the complete output.
3. Run `bash setup/cli/ipmctl.sh install` again and confirm it reports the
   matching installation rather than rebuilding.
4. Run `bash setup/cli/ipmctl.sh verify` and retain all four labeled probe
   sections.
5. Confirm the expected version, complete linkage, receipt and manifest,
   detected DIMMs, topology, memory resources, and that any current or pending
   goal is understood.
6. Only then run the LLM host validator with `--require-ipmctl` and, when
   appropriate, `--require-memory-mode`.

After review, merge, and `www` publication, fetch the published runner and run
`verify` again. Reinstall from the public URL only if the published content
differs from the accepted candidate or a reinstall is intentional.

GitHub Actions checks the static runner, playbook, patch checksums, YAML, and
publication contract. It deliberately does not rebuild archived Intel source
or pretend to validate PMem hardware in a hosted runner.
