from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence

from redline import __version__
from redline.errors import RedlineError
from redline.pipeline import check_lease
from redline.profiles import DEFAULT_PROFILE, PROFILE_CHOICES
from redline.report import render_text


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command == "check":
        try:
            report = check_lease(
                args.path,
                profile=args.profile,
                deal_path=args.deal,
                thread_path=args.thread,
                context=args.context,
                context_path=args.context_file,
                fail_on=args.fail_on,
                provider=args.provider,
                model=args.model,
                base_url=args.base_url,
            )
        except RedlineError as exc:
            print(f"redline: {exc}", file=sys.stderr)
            if args.json:
                print(json.dumps({"error": {"code": exc.code, "message": str(exc)}}, indent=2))
            return 2

        if args.json:
            print(json.dumps(report.model_dump(mode="json"), indent=2))
        else:
            print(render_text(report), end="")
        return report.exit_code

    parser.error("unknown command")
    return 2


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="redline",
        description=(
            "Review documents with cited reports. The current deterministic "
            "default profile validates general commercial lease terms and math."
        ),
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="check a lease document with a review profile")
    check.add_argument("path", help="path to an extractable-text PDF document")
    check.add_argument(
        "--profile",
        choices=PROFILE_CHOICES,
        default=DEFAULT_PROFILE,
        help="review profile to run; lease-general is broader, lease-math is the narrow math lane",
    )
    check.add_argument("--deal", help="optional deal.yaml path")
    check.add_argument("--context", help="optional advisory focus for an AI judgment pass")
    check.add_argument("--context-file", help="path to review context text for the advisory pass")
    check.add_argument(
        "--thread",
        help="path to a negotiation-thread text file to distill into deal terms + advisory items",
    )
    check.add_argument(
        "--provider",
        choices=["codex", "openai", "ollama", "anthropic"],
        default=None,
        help="LLM provider for extraction/focus; defaults to REDLINE_LLM_PROVIDER or codex",
    )
    check.add_argument(
        "--fail-on",
        choices=["error", "warn", "verify", "advisory"],
        default="error",
        help="exit-code threshold; verify also fails on COULD_NOT_VERIFY",
    )
    check.add_argument("--model", help="provider model override")
    check.add_argument(
        "--base-url",
        help="provider base URL override, e.g. Ollama URL; for codex, path to codex binary",
    )
    check.add_argument("--json", action="store_true", help="print structured JSON")
    return parser


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
