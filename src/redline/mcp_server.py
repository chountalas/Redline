from __future__ import annotations

from typing import Any

from redline.pipeline import check_lease as run_check_lease
from redline.report import FailOn


def main() -> None:
    try:
        from mcp.server.fastmcp import FastMCP
    except ImportError as exc:  # pragma: no cover
        raise SystemExit(
            "MCP support is included in the Homebrew app cask. From source, run: "
            "uv sync --extra mcp"
        ) from exc

    mcp = FastMCP("redline")

    @mcp.tool()
    def check_lease(
        path: str,
        profile: str = "lease-general",
        deal_path: str | None = None,
        thread_path: str | None = None,
        context: str | None = None,
        context_path: str | None = None,
        fail_on: FailOn = "error",
        provider: str | None = None,
        model: str | None = None,
        base_url: str | None = None,
    ) -> dict[str, Any]:
        """Review a lease PDF with Redline. Profiles: lease-general or lease-math."""

        report = run_check_lease(
            path,
            profile=profile,
            deal_path=deal_path,
            thread_path=thread_path,
            context=context,
            context_path=context_path,
            fail_on=fail_on,
            provider=provider,
            model=model,
            base_url=base_url,
        )
        return report.model_dump(mode="json")

    mcp.run()


if __name__ == "__main__":  # pragma: no cover
    main()
