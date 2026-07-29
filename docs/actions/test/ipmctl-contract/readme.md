---
title: ipmctl contract actions
section: Actions / Test / ipmctl
source_path: actions/test.ipmctl-contract.sh
---

# ipmctl contract actions

`actions/test.ipmctl-contract.sh` checks the runner interface, exact ipmctl and
edk2 pins, fixture normalization, facts, host integration, and destructive
goal isolation. GitHub Actions enables remote tag verification.

`actions/test.ipmctl-source-build.sh` runs only in the Debian 13 GitHub Actions
container. It builds the exact reviewed Release tuple, installs into an
isolated prefix, runs Intel's pinned `updateedk.sh` and `patch_OS.sh` sequence,
injects the reviewed `BUILDNUM`, confirms that Release still enables `-Werror`,
checks the exact `ipmctl version`, and rejects unexpected patch targets or
unresolved libraries.

Neither action runs PMem discovery or creates a goal. Hardware acceptance is
performed separately on the remote Optane host.
