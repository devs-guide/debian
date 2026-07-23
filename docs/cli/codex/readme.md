---
title: Codex CLI runner
section: CLI / Codex
source_path: setup/cli/codex.sh
script_url: https://devs-guide.github.io/debian/setup/cli/codex.sh
---

# Codex CLI runner

Sets up the project’s Node plus Codex CLI feature. It supports `preflight` and
`apply` modes and is independent of the baseline bootstrap playlist.

## Preflight

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/codex.sh | \
  env DEBIAN_CLI_CODEX_MODE=preflight bash
```

## Shared Codex CLI installation

```bash
wget -qO- https://devs-guide.github.io/debian/setup/cli/codex.sh | \
  env DEBIAN_CLI_CODEX_MODE=apply \
      DEBIAN_CLI_CODEX_NODE_VERSION='lts/*' \
      DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE=shared \
      DEBIAN_CLI_CODEX_NODE_CREATE_SYSTEM_SYMLINKS=1 \
      DEBIAN_CLI_CODEX_PACKAGE='@openai/codex' \
      DEBIAN_CLI_CODEX_VERSION=latest \
      DEBIAN_CLI_CODEX_INSTALL_DOCS_MCP=1 \
      DEBIAN_CLI_CODEX_DOCS_MCP_NAME=openaiDeveloperDocs \
      DEBIAN_CLI_CODEX_DOCS_MCP_URL=https://developers.openai.com/mcp \
      bash
```

| Variable | Purpose |
| --- | --- |
| `DEBIAN_CLI_CODEX_MODE` | Selects the read-only `preflight` or mutating `apply` mode. |
| `DEBIAN_CLI_CODEX_NODE_VERSION` | Selects the NVM Node version; use a fixed version instead of `lts/*` when reproducibility matters. |
| `DEBIAN_CLI_CODEX_NODE_INSTALL_SCOPE` | Uses the shared NVM install for a host-wide command. |
| `DEBIAN_CLI_CODEX_PACKAGE` / `DEBIAN_CLI_CODEX_VERSION` | Selects the npm package and version. Replace `latest` with an approved exact version when required. |
| `DEBIAN_CLI_CODEX_INSTALL_DOCS_MCP` | Opts into the documented OpenAI developer-docs MCP configuration. |

After an apply run, open a new shell and run `codex --version`. Authenticate
through the Codex CLI’s normal supported flow; this runner does not store an
API key for you.
