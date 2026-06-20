# Changelog

## 0.1.3 - 2026-06-19

- Add `lease-general` as the default profile while keeping `lease-math` for the narrow billboard/per-display-face lane.
- Add deterministic general lease coverage for permitted use, assignment/sublease, maintenance, insurance, cure periods, notices, additional rent/CAM, renewal notice windows, and termination asymmetry.
- Generalize the Mac app shell around document review while keeping the active review profile explicit.
- Add easier review-context entry, context templates, clipboard paste, and long-context `--context-file` handling.
- Add profile/document/context/coverage metadata to reports.
- Prevent silent re-checks when prior context was intentionally not saved.
- Route `could_not_verify` findings into the Mac report even when the engine does not duplicate them in deterministic findings.

## 0.1.2 - 2026-06-06

- Clarify Homebrew as the public install path for the app, CLI, MCP server, and provider adapters.
- Replace future PyPI install guidance in docs with Homebrew/source-checkout instructions.
- Use SDK-free HTTPS adapters for OpenAI and Anthropic so Homebrew installs do not need native SDK dependencies.

## 0.1.1 - 2026-06-04

- Replace placeholder owner and bundle metadata with public release metadata.
- Make release checksum files portable by writing artifact basenames instead of local build paths.
- Rename demo-party sample data to unmistakably synthetic names.

## 0.1.0 - 2026-06-04

- Scaffold open-source alpha package.
- Add deterministic data models, rule registry, report rendering, CLI, provider-backed extractor, optional focus pass, and optional MCP server.
- Add structured model-provider extraction and advisory focus calls.
- Replace provider-specific extraction with provider-agnostic Codex CLI, OpenAI API, Ollama, and explicit Anthropic adapters.
- Add native SwiftUI macOS wrapper for local PDF selection and Redline runs.
- Add signed/notarized macOS release packaging and Homebrew app cask support.
- Add synthetic tests for R1-R6, PDF text extraction, mocked provider extraction, CLI JSON output, and report exit-code behavior.
- Add release-safety scanner for secrets and accidental environment files.
- Add public privacy, security, notice, and open-source readiness documentation.
