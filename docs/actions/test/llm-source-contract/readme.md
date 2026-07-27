---
title: LLM reviewed-source contract action
section: Actions / Test / LLM source contract
source_path: actions/test.llm-source-contract.sh
---

# LLM reviewed-source contract action

GitHub Actions checks the llama.cpp and KTransformers runner interfaces, exact
source-profile matrices, Ansible ownership boundaries, fact paths, and
documentation through `actions/validate.runtime.sh`.

The GitHub Pages workflow sets `LLM_SOURCE_NETWORK_VERIFY=1`. In that Actions
environment the test also resolves the reviewed Git tags, verifies the
KTransformers SGLang submodule object, downloads the official Python source
archive, and checks its committed SHA-256.

CUDA/SM86 builds, Ice Lake instruction checks, and model smokes remain remote
server acceptance tests. They are not run on a developer workstation.
