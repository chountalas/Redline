# MCP Server

Homebrew installs the MCP server with the app cask:

```bash
brew install --cask chountalas/tap/redline-app
```

From a source checkout, install the MCP extra:

```bash
uv sync --extra mcp
```

Example client config:

```json
{
  "mcpServers": {
    "redline": {
      "command": "uv",
      "args": ["run", "redline-mcp"],
      "cwd": "/path/to/Redline"
    }
  }
}
```

For a Homebrew install, use `"command": "redline-mcp"` with no `cwd`. The command is linked from the engine bundled inside `Redline.app`.

You can also run the module directly:

```bash
uv run python -m redline.mcp_server
```

Tool:

```text
check_lease(
  path,
  profile = "lease-general",
  deal_path = null,
  context = null,
  context_path = null,
  thread_path = null,
  fail_on = "error",
  provider = null,
  model = null,
  base_url = null
)
```

It returns the same structured payload as `redline check --json`.

`profile` may be `lease-general` or `lease-math`. `context` is an advisory focus string. `context_path` points to longer review context text for the advisory pass. `thread_path` points to review context text; for lease profiles it distills supported numeric comparison terms for deterministic checks and keeps qualitative commitments as advisory watch items.

`provider = null` uses Redline's default provider, currently `codex`.
