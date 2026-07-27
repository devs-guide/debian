---
title: Versioned llama.cpp runner
section: CLI / LLM / llama.cpp
source_path: setup/cli/llm/llamacpp.sh
script_url: https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh
---

# Versioned llama.cpp runner

`llamacpp.sh` builds one exact reviewed llama.cpp source tuple for the accepted
LLM host, records the compiled command capabilities, and optionally runs one
bounded prompt against an existing local GGUF file.

llama.cpp is an independently owned feature and a process gate before the
KTransformers toolchain. KTransformers does not import, execute, or require
this installation.

## Modes

| Mode | Behavior |
| --- | --- |
| `preflight` | Validates the requested compatibility-matrix tuple and reports producer facts and the remote tag without cloning source. |
| `apply` | Stages the exact source as the invoking user, optionally installs build tools, builds SM86 binaries, validates them, and promotes the profile. |
| `validate` | Rechecks the existing source, binaries, devices, hashes, and capabilities without a package transaction or source fetch. |
| `smoke` | Runs one deterministic bounded `llama-cli` query against an existing canonical local GGUF. |
| `upgrade` | Builds another reviewed compatibility profile side-by-side and promotes it only after validation. |

## Reviewed source and future builds

The initial profile is:

```text
profile: b10075-icelake-sm86
repository: https://github.com/ggml-org/llama.cpp.git
release: b10075
commit: 76f46ad29d61fd8c1401e8221842934bf62a6064
```

Repository URL, release, and full commit are explicit inputs. A future build
does not require new clone logic: add its exact tuple to the reviewed
compatibility matrix, contract-test it in GitHub Actions, publish it, and pass
the new values to the runner. Floating branches, shortened commits, repository
credentials, and unreviewed URL/commit combinations fail before sudo.

## Remote sequence

Read-only preflight:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
  bash -s -- preflight \
    --matrix-profile=b10075-icelake-sm86 \
    --repository-url=https://github.com/ggml-org/llama.cpp.git \
    --release=b10075 \
    --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
    --build-profile=icelake-sm86 \
    --cuda-architectures=86
```

Build the reviewed source:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
  bash -s -- apply \
    --matrix-profile=b10075-icelake-sm86 \
    --repository-url=https://github.com/ggml-org/llama.cpp.git \
    --release=b10075 \
    --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
    --build-profile=icelake-sm86 \
    --cuda-architectures=86 \
    --source-dir=/opt/src/llamacpp/b10075-icelake-sm86 \
    --build-dir=/opt/build/llamacpp/b10075-icelake-sm86 \
    --install-dir=/opt/llama.cpp/b10075-icelake-sm86 \
    --install-build-tools
```

Validate with no package or source transaction:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
  sudo bash -s -- validate \
    --matrix-profile=b10075-icelake-sm86 \
    --repository-url=https://github.com/ggml-org/llama.cpp.git \
    --release=b10075 \
    --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
    --build-profile=icelake-sm86 \
    --cuda-architectures=86 \
    --source-dir=/opt/src/llamacpp/b10075-icelake-sm86 \
    --build-dir=/opt/build/llamacpp/b10075-icelake-sm86 \
    --install-dir=/opt/llama.cpp/b10075-icelake-sm86 \
    --no-install-build-tools
```

Run the human-acceptance smoke after placing a small GGUF locally:

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/llm/llamacpp.sh | \
  bash -s -- smoke \
    --matrix-profile=b10075-icelake-sm86 \
    --repository-url=https://github.com/ggml-org/llama.cpp.git \
    --release=b10075 \
    --commit=76f46ad29d61fd8c1401e8221842934bf62a6064 \
    --build-profile=icelake-sm86 \
    --cuda-architectures=86 \
    --source-dir=/opt/src/llamacpp/b10075-icelake-sm86 \
    --build-dir=/opt/build/llamacpp/b10075-icelake-sm86 \
    --install-dir=/opt/llama.cpp/b10075-icelake-sm86 \
    --model=/models/gguf/smoke/model.gguf \
    --prompt="Reply with exactly: llama.cpp smoke passed" \
    --max-tokens=32 \
    --ctx-size=2048 \
    --threads=36 \
    --threads-batch=36 \
    --gpu-layers=auto \
    --split-mode=layer \
    --tensor-split=1,1 \
    --offline \
    --check-tensors \
    --smoke-timeout-seconds=900 \
    --seed=1
```

The runner requests sudo once through `/dev/tty` for managed modes. Source is
downloaded and verified as the invoking user first; delegated-root execution
does not repeat the upstream download. The runner never downloads a model.

## Flag reference

| Flag | Behavior |
| --- | --- |
| `--matrix-profile=PROFILE` | Selects one reviewed compatibility record. |
| `--repository-url=HTTPS_GIT_URL` | Exact credential-free source repository ending in `.git`. |
| `--release=TAG` | Exact reviewed tag. |
| `--commit=FULL_40_CHARACTER_SHA` | Exact lowercase source commit. |
| `--build-profile=PROFILE` | Reviewed CPU/CUDA build policy name. |
| `--cuda-architectures=LIST` | Reviewed CUDA architecture list; initial value is `86`. |
| `--source-dir=/opt/src/llamacpp/PATH` | Optional constrained source destination. |
| `--build-dir=/opt/build/llamacpp/PATH` | Optional constrained build destination. |
| `--install-dir=/opt/llama.cpp/PATH` | Optional constrained versioned installation. |
| `--clean-build` | Removes only the selected managed build directory before rebuilding. |
| `--install-build-tools` | Installs the opt-in `llamacpp_build` package group during apply/upgrade. |
| `--no-install-build-tools` | Forbids a package transaction. |
| `--model=/absolute/local/model.gguf` | Existing canonical, non-symlink local model for `smoke`. |
| `--prompt=TEXT` | Bounded smoke prompt. |
| `--max-tokens=N` | Maximum generated smoke tokens. |
| `--ctx-size=N` | Smoke context allocation. |
| `--threads=N` | Decode CPU threads. |
| `--threads-batch=N` | Batch CPU threads. |
| `--gpu-layers=auto\|all\|N` | Managed mapping to `--n-gpu-layers`. |
| `--split-mode=none\|layer\|row\|tensor` | Multi-GPU split mode. |
| `--tensor-split=RATIOS` | Comma-separated GPU split ratios. |
| `--fit-target=MIB_LIST` | Optional per-device fit target accepted only when the pinned binary advertises it. |
| `--offline` | Requires local-only model behavior. |
| `--check-tensors` | Enables tensor-data validation during model load. |
| `--seed=N` | Deterministic smoke seed. |
| `--cpu-moe` | Moves all MoE expert weights to CPU when supported. |
| `--n-cpu-moe=N` | Moves the first N MoE layers to CPU; mutually exclusive with `--cpu-moe`. |
| `--smoke-timeout-seconds=N` | Remote-host wall-clock limit for one model smoke; default is 900 seconds. |
| `--help` | Prints usage without staging. |

## Flag interaction notes

- The matrix profile, repository URL, release, full commit, build profile, and
  CUDA architecture form one reviewed tuple. Supplying a valid value from a
  different tuple is rejected.
- Path flags select versioned managed locations; they do not permit arbitrary
  filesystem destinations or relax source verification.
- `--install-build-tools` is relevant only to `apply` and `upgrade`.
  `validate` and `smoke` should use the already-installed runtime.
- `--clean-build` removes only the selected build directory. It does not remove
  the reviewed source, installed profile, facts, or model files.
- `--cpu-moe` and `--n-cpu-moe` are mutually exclusive and are accepted only
  when the pinned binary advertises the corresponding option.
- `--fit-target` is optional and fails closed when the installed binary does
  not expose that capability.
- “Local GGUF” means local to the remote GPU server. The runner never downloads
  or discovers a model on the development workstation.

## Facts and verification

The runner owns:

```text
/etc/ansible/debian/facts/llamacpp.yml
/etc/ansible/debian/env/llamacpp.sh
/opt/llama.cpp/current
```

GitHub Actions verifies matrix structure, source identities, runner staging,
and published paths. Compilation, CUDA-device checks, and local-model smoke
acceptance run on the remote Ice Lake/NVIDIA host rather than a development
workstation.
