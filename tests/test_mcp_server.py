from __future__ import annotations

import importlib


def test_mcp_server_module_imports() -> None:
    module = importlib.import_module("redline.mcp_server")

    assert callable(module.main)

