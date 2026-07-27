---
title: KTransformers heterogeneous runtime runner
section: CLI / LLM / KTransformers
source_path: setup/cli/llm/ktransformers.sh
script_url: https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh
---

# KTransformers heterogeneous runtime runner

`ktransformers.sh` builds an isolated, exact-source KTransformers, KT-Kernel,
and SGLang-KT environment after host and llama.cpp acceptance. It performs
model-free imports and capability checks only; model acquisition, expert
placement, server startup, and the 80B MoE smoke remain separate features.

The standalone llama.cpp feature is not a technical dependency. KTransformers
does not consume `llamacpp.yml`, and its internal `LLAMAFILE` method does not
execute `/opt/llama.cpp`.

## Memory semantics

KTransformers can keep selected hot experts in GPU VRAM while remaining cold
experts execute from CPU-visible host memory. On an Intel Optane host in
Memory Mode, DDR caching is controlled by the processor memory controller.
The runner does not expose a flag claiming to place experts directly in DDR.

## Reviewed source profile

```text
profile: v0.6.3-icelake-sm86-source
KTransformers repository: https://github.com/kvcache-ai/ktransformers.git
KTransformers release: v0.6.3
KTransformers commit: ce7c3ddbe93f7ac1f992375eed54058bbc512646
SGLang-KT repository: https://github.com/kvcache-ai/sglang.git
SGLang-KT commit: 8b636f9008dbad58c0a8e481b03e794739e6c146
Python: 3.12.3
CUDA architecture: 86
CPU profile: icelake-avx512-vnni
```

Future repositories and commits use the same command interface. Add the exact
KTransformers/SGLang/Python tuple to the reviewed matrix, verify it in GitHub
Actions and on the remote host, then select the new profile. Floating branches,
short commits, credentials, and unreviewed source combinations are rejected.

## Remote sequence

Read-only preflight:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
  bash -s -- preflight \
    --matrix-profile=v0.6.3-icelake-sm86-source \
    --repository-url=https://github.com/kvcache-ai/ktransformers.git \
    --release=v0.6.3 \
    --commit=ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
    --sglang-repository-url=https://github.com/kvcache-ai/sglang.git \
    --sglang-commit=8b636f9008dbad58c0a8e481b03e794739e6c146 \
    --install-profile=source \
    --python-version=3.12.3 \
    --cuda-architectures=86 \
    --cpu-profile=icelake-avx512-vnni
```

Initial source build with explicit online dependency acknowledgement:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
  bash -s -- apply \
    --matrix-profile=v0.6.3-icelake-sm86-source \
    --repository-url=https://github.com/kvcache-ai/ktransformers.git \
    --release=v0.6.3 \
    --commit=ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
    --sglang-repository-url=https://github.com/kvcache-ai/sglang.git \
    --sglang-commit=8b636f9008dbad58c0a8e481b03e794739e6c146 \
    --install-profile=source \
    --python-version=3.12.3 \
    --allow-online-dependencies \
    --cuda-architectures=86 \
    --cpu-profile=icelake-avx512-vnni \
    --source-dir=/opt/src/ktransformers/v0.6.3-icelake-sm86-source \
    --build-dir=/opt/build/ktransformers/v0.6.3-icelake-sm86-source \
    --install-dir=/opt/venvs/ktransformers-v0.6.3-icelake-sm86-source \
    --install-build-tools
```

Validate the installed model-free environment without another dependency
transaction:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/ktransformers.sh | \
  sudo bash -s -- validate \
    --matrix-profile=v0.6.3-icelake-sm86-source \
    --repository-url=https://github.com/kvcache-ai/ktransformers.git \
    --release=v0.6.3 \
    --commit=ce7c3ddbe93f7ac1f992375eed54058bbc512646 \
    --sglang-repository-url=https://github.com/kvcache-ai/sglang.git \
    --sglang-commit=8b636f9008dbad58c0a8e481b03e794739e6c146 \
    --install-profile=source \
    --python-version=3.12.3 \
    --no-online-dependencies \
    --cuda-architectures=86 \
    --cpu-profile=icelake-avx512-vnni \
    --source-dir=/opt/src/ktransformers/v0.6.3-icelake-sm86-source \
    --build-dir=/opt/build/ktransformers/v0.6.3-icelake-sm86-source \
    --install-dir=/opt/venvs/ktransformers-v0.6.3-icelake-sm86-source \
    --no-install-build-tools
```

The runner requests sudo once through `/dev/tty`. KTransformers, its recursive
submodules, and Python source are downloaded and verified as the invoking user
before delegated-root execution. The remote playbook keeps the reviewed Git
tree pristine under `/opt/src`, copies it to a mutable `/opt/build` worktree,
and independently rechecks the managed Python archive SHA-256 before building.
The first explicitly online bootstrap records `pip freeze --all`; use that
evidence to create an approved wheelhouse before any model-bearing phase.

For a later reviewed rebuild, replace `--allow-online-dependencies` in the
filled `apply` command with:

```bash
    --wheelhouse=/models/manifests/ktransformers-wheelhouse \
    --no-online-dependencies
```

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--matrix-profile=PROFILE` | Selects one exact reviewed source/toolchain record. |
| `--repository-url=HTTPS_GIT_URL` | Exact KTransformers repository ending in `.git`. |
| `--release=TAG` | Exact KTransformers release tag. |
| `--commit=FULL_40_CHARACTER_SHA` | Full lowercase KTransformers commit. |
| `--sglang-repository-url=HTTPS_GIT_URL` | Exact reviewed SGLang-KT submodule repository. |
| `--sglang-commit=FULL_40_CHARACTER_SHA` | Full lowercase SGLang-KT submodule commit. |
| `--install-profile=source` | Initial authoritative source-build profile. |
| `--python-version=X.Y.Z` | Exact reviewed Python 3.12 patch. |
| `--wheelhouse=/absolute/local/directory` | Uses an approved local dependency source. |
| `--allow-online-dependencies` | Explicitly permits the exact-source upstream installers to resolve Python dependencies online. |
| `--no-online-dependencies` | Forbids online Python dependency resolution. |
| `--cuda-architectures=LIST` | Reviewed CUDA architecture list; initial value is `86`. |
| `--cpu-profile=PROFILE` | Reviewed host CPU instruction profile. |
| `--source-dir=/opt/src/ktransformers/PATH` | Optional constrained source destination. |
| `--build-dir=/opt/build/ktransformers/PATH` | Optional constrained build destination. |
| `--install-dir=/opt/venvs/ktransformers-PATH` | Optional constrained environment destination. |
| `--clean-build` | Removes only the selected build and unpromoted environment. |
| `--install-build-tools` | Installs only the opt-in `ktransformers_build` package group. |
| `--no-install-build-tools` | Forbids a package transaction. |
| `--help` | Prints usage without staging. |

## Flag interaction notes

- The KTransformers URL/tag/commit, SGLang URL/commit, Python version, CPU
  profile, CUDA architecture, and matrix profile are one reviewed tuple.
- `apply` and `upgrade` require either an approved `--wheelhouse` or the
  explicit `--allow-online-dependencies` bootstrap acknowledgement.
  `--no-online-dependencies` is the fail-closed default.
- A wheelhouse path is consumed by the managed LLM owner and must already
  contain the reviewed dependencies. This runner does not create or populate
  that directory.
- `--source-dir` stores the pristine detached source, `--build-dir` contains
  the mutable installation worktree, and `--install-dir` contains the isolated
  Python environment.
- `--clean-build` removes only the selected build worktree and unpromoted
  virtual environment. It refuses to remove
  `/opt/venvs/ktransformers-current` and does not delete pristine source, the
  managed Python archive, models, or producer facts.
- `--install-build-tools` enables only the opt-in Debian package group during
  `apply` or `upgrade`; it never changes NVIDIA or CUDA policy.
- Every mode remains model-free. Model paths, expert counts, and server launch
  settings belong to later KTransformers model and smoke runners.

## Facts and acceptance

The runner owns:

```text
/etc/ansible/debian/facts/ktransformers.yml
/etc/ansible/debian/env/ktransformers.sh
/opt/venvs/ktransformers-current
```

Facts record full source URLs and commits, Python and dependency inventory,
CPU/CUDA policy, selected UUIDs, `kt doctor`, imports, and generated SGLang-KT
capabilities. They deliberately report `model_ready: false`.

GitHub Actions owns source/checksum/matrix and publication verification.
CUDA 13.1, SM86, AVX-512/VNNI, imports, and later model acceptance run on the
remote server. No local development-machine compilation is part of acceptance.
