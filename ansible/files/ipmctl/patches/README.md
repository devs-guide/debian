# ipmctl Debian 13 compatibility patches

These patches are applied only to the pinned source tuple documented by the
ipmctl playbook. Installation never discovers or downloads patches at runtime.

- `0001-edk2-stable202511-host-os-build.patch` is regenerated against EDK2
  commit `46548b1adac82211d8d11da12dd914f41e7aa775`. It preserves that
  commit's CRLF `MdePkg/Include/Base.h` blob and implements the host-build
  guards carried by meta-intel. The binary Git delta keeps line endings exact;
  the playbook verifies its SHA-256
  `ac6f0ea143c357c582135472defe8e936a63d7997221a29d4d0e4c349d7ac013`,
  single target, and pre/postimage values. Original attribution and status are
  retained from the [exact meta-intel source](https://github.com/YoeDistro/meta-intel/blob/8877caca6b1fe6efe33c756698ce6ecdcaea2238/dynamic-layers/openembedded-layer/recipes-support/ipmctl/ipmctl/0001-Ignore-STATIC_ASSERTs-and-NULL-define-for-os-and-ut-builds.patch).
- `0002-ipmctl-disable-c-release-werror.patch` and
  `0003-ipmctl-remove-pie-from-shared-linker-flags.patch` are the meta-intel
  patches at revision `8877caca6b1fe6efe33c756698ce6ecdcaea2238`.
  Their SHA-256 values are respectively
  `d1928dc874219578abbc9eab5cc7a826ccf88457bd148f268aff367d134321b8`
  and `f926a6b07ad33b09f09032e6fd06a9229855d9d0501cfc7e67ecbb4c3c28a031`.

Provenance:

- https://github.com/YoeDistro/meta-intel/tree/8877caca6b1fe6efe33c756698ce6ecdcaea2238/dynamic-layers/openembedded-layer/recipes-support/ipmctl/ipmctl
- https://github.com/YoeDistro/meta-intel/blob/8877caca6b1fe6efe33c756698ce6ecdcaea2238/dynamic-layers/openembedded-layer/recipes-support/ipmctl/ipmctl/0001-CMakeLists-disable-Werror.patch
- https://github.com/YoeDistro/meta-intel/blob/8877caca6b1fe6efe33c756698ce6ecdcaea2238/dynamic-layers/openembedded-layer/recipes-support/ipmctl/ipmctl/0001-CMakeLists-fix-build-failure-by-removing-pie-from-sh.patch
- https://github.com/intel/ipmctl/releases/tag/v03.00.00.0538
- https://github.com/tianocore/edk2/releases/tag/edk2-stable202511
