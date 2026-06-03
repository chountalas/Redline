# MCP Server

From a source checkout, install the MCP extra:

```bash
uv sync --extra mcp
```

After package publication, install with the MCP extra:

```bash
pip install "redline-lease[mcp]"
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

For a package install, use `"command": "redline-mcp"` with no `cwd`.

You can also run the module directly:

```bash
uv run python -m redline.mcp_server
```

Tool:

```text
check_lease(
  path,
  deal_path = null,
  context = null,
  fail_on = "error",
  provider = null,
  model = null,
  base_url = null
)
```

It returns the same structured payload as `redline check --json`.

`provider = null` uses Redline's default provider, currently `codex`.
