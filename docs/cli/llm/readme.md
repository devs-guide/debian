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

KTransformers, model-catalog, smoke-test, llama.cpp, and Ollama runners are
later phases. Phase 1 installs none of those runtimes and downloads no models.
