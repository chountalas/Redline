# Mac App

Redline includes a SwiftUI macOS wrapper for local review workflows. It is a shell over the Python CLI, not a separate validator.

The public app install is the Homebrew cask. The source checkout can also build a development app bundle.

## Requirements

- macOS 14 or newer
- For public installs: Homebrew
- Xcode command line tools / Swift toolchain
- `uv`
- The provider you choose:
  - Codex CLI login for the default Codex provider
  - `OPENAI_API_KEY` for OpenAI API
  - Ollama running locally for Ollama
  - `ANTHROPIC_API_KEY` plus the Anthropic extra for Anthropic

## Install

Install the CLI:

```bash
brew install chountalas/tap/redline
```

Install the Mac app:

```bash
brew install --cask chountalas/tap/redline-app
```

The cask installs `Redline.app` into `/Applications` and depends on the CLI formula. That keeps the GUI, CLI, and MCP server on the same validator engine.

## Development Run

```bash
./script/build_and_run.sh
```

The script builds `macos/RedlineMac`, stages `dist/Redline.app`, and opens it as a foreground macOS app.

Install a development build into `/Applications`:

```bash
./script/build_and_run.sh --install
```

Other modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## Workflow

- Choose or drop a lease PDF.
- Optionally choose a `deal.yaml`.
- Optionally enter a focus prompt for advisory findings.
- Choose a provider: Codex subscription, OpenAI API, Ollama local, or explicit Anthropic.
- Enter an API key only for remote providers.
- Run the check and review deterministic and advisory findings.

The app passes the API key to the `redline check` process as `REDLINE_API_KEY`. It does not save the key.

The document library, per-finding notes, review state, and non-secret settings are saved under the user's Application Support directory. API keys are excluded from Redline persistence.

## Architecture

The app invokes:

```bash
uv run redline check <lease.pdf> --json --provider <provider>
```

from the repository root when launched from a source checkout. When the app is installed outside a checkout, it invokes the installed `redline` CLI directly. With the default Codex provider, this uses the local authenticated `codex` CLI and does not require an API key. This keeps the CLI, MCP server, and Mac app on the same rule engine and extractor path.
