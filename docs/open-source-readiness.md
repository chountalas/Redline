# Open-Source Readiness

Use this checklist before making the repository public or cutting a release.

## Required Checks

```bash
swift build && swift test
REDLINE_REAL_ENGINE_TESTS=1 REDLINE_REAL_LEASE_PDF=/path/to/uncommitted/lease.pdf swift test --filter RealEngineIntegrationTests/testSwiftRunnerCompletesRealLeaseWhenEnabled
uv run pytest -q
uv run mypy src
uv run ruff check .
uv run python scripts/check_release_safety.py
```

Run the Swift commands from `macos/RedlineMac`. Run the Python and safety commands from the repository root.

## Manual Review

- No real leases, exported reports, or screenshots with confidential terms are staged.
- No API keys, access tokens, `.env` files, or provider credentials are staged.
- No private workflow notes, inbox references, customer names, or local-only paths are staged.
- README install instructions match the actual release state.
- `PRIVACY.md` and `SECURITY.md` still reflect the current provider behavior.
- The macOS app launches via `./script/build_and_run.sh --verify`.

## Distribution State

The source checkout is usable now. Public binary distribution, notarization, Homebrew packaging, and PyPI publication should each get a separate release check before announcement.
