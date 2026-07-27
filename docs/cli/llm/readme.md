---
title: LLM feature runners
section: CLI / LLM
source_path: setup/cli/llm
description: Shared host contracts and opt-in LLM runtime features.
---

# LLM feature runners

LLM runners share the `setup/cli/llm/<feature>.sh` namespace. Each feature
owns its own facts and managed artifacts while consuming earlier contracts.

- [Host readiness](/debian/cli/llm/host/) — CPU, NUMA, memory, reserve, and
  GPU-producer prerequisites.
- [llama.cpp](/debian/cli/llm/llamacpp/) — exact-source CPU/CUDA build and
  opt-in local-GGUF smoke.
- [KTransformers](/debian/cli/llm/ktransformers/) — exact-source KT-Kernel and
  SGLang-KT model-free toolchain.

The accepted order is host readiness, standalone llama.cpp build/smoke,
KTransformers toolchain, model catalog/acquisition, then the bounded 80 GB MoE
smoke. llama.cpp and KTransformers accept exact reviewed repository URLs and
full commits so future builds can be added through compatibility-matrix
updates without following floating upstream branches.
