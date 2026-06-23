# Mac App

Redline includes a SwiftUI macOS wrapper for local review workflows. It runs the same Python validator engine as the CLI.

The public install is the Homebrew cask. It installs the app and links `redline` and `redline-mcp` from the engine bundled inside `Redline.app`. The source checkout can also build a development app bundle.

## Requirements

- macOS 14 or newer
- For public installs: Homebrew; the cask installs the `python@3.13` runtime dependency
- Xcode command line tools / Swift toolchain
- `uv`
- The provider you choose:
  - Codex CLI login for the default Codex provider
  - `OPENAI_API_KEY` for OpenAI API
  - Ollama running locally for Ollama
  - `ANTHROPIC_API_KEY` for Anthropic

## Install Everything

```bash
brew install --cask chountalas/tap/redline-app
```

The cask installs `Redline.app` into `/Applications`, installs the Homebrew `python@3.13` runtime dependency, and links the bundled `redline` and `redline-mcp` commands. Provider adapters for Codex, Ollama, OpenAI, and Anthropic are included.

Verify the install:

```bash
redline --version
```

Upgrade later:

```bash
brew upgrade --cask chountalas/tap/redline-app
```

## CLI Only

The app cask includes the CLI. The historical formula is only for terminal-only installs:

```bash
brew install chountalas/tap/redline
```

## Development Run

```bash
./script/build_and_run.sh
```

The script builds `macos/RedlineMac`, stages `dist/Redline.app`, and opens it as a foreground macOS app backed by the source checkout.

Install a development build into `/Applications` with a bundled engine:

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

- Choose or drop a PDF document.
- Choose a review profile: General lease or Lease math.
- Optionally choose a comparison sheet (`deal.yaml` for the lease profile).
- Optionally enter comparison context or a focus prompt for advisory findings.
- Choose a provider: Codex subscription, OpenAI API, Ollama local, or explicit Anthropic.
- Enter an API key only for remote providers.
- Run the check and review deterministic and advisory findings.

The app passes the API key to the `redline check` process as `REDLINE_API_KEY`. It does not save the key.

The document library, per-finding notes, review state, and non-secret settings are saved under the user's Application Support directory. API keys are excluded from Redline persistence.

## Architecture

The app invokes:

```bash
uv run redline check <document.pdf> --json --profile <profile> --provider <provider>
```

from the repository root when launched from a source checkout. Long review context is passed through a temporary `--context-file`, not as a long command-line argument. Release and installed development apps invoke `Contents/Resources/Engine/bin/redline` from inside `Redline.app`; the Homebrew cask links that same bundled executable as `redline`. With the default Codex provider, this uses the local authenticated `codex` CLI and does not require an API key. This keeps the CLI, MCP server, and Mac app on the same rule engine and extractor path. The default production CLI profile is `lease-general`; `lease-math` remains available for the narrower per-display-face math lane.
