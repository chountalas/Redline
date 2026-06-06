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
./script/package_release.sh
```

Run the Swift commands from `macos/RedlineMac`. Run the Python and safety commands from the repository root.

## Manual Review

- No real leases, exported reports, or screenshots with confidential terms are staged.
- No API keys, access tokens, `.env` files, or provider credentials are staged.
- No private workflow notes, inbox references, customer names, or local-only paths are staged.
- README install instructions match the actual release state.
- `PRIVACY.md` and `SECURITY.md` still reflect the current provider behavior.
- The macOS app launches via `./script/build_and_run.sh --verify`.
- Release builds pass `codesign --verify --deep --strict dist/Redline.app`.
- Homebrew formula and cask audit cleanly from the tap checkout.

## Distribution State

Homebrew is the supported public install path for the CLI and app. Formula-only dependency changes can ship as a Homebrew revision. Public notarized app distribution should be cut with `./script/release.sh` before updating the cask version or URL. PyPI publication is not complete yet.
