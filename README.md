<p align="center">
  <img src="docs/assets/redline-icon.png" width="88" alt="Redline app icon">
</p>

# Redline

Redline is a cited document-review workspace for commercial lease review. It extracts facts with a configurable model provider, then runs deterministic checks over the extracted terms so the verdict is based on rule assertions, arithmetic, and cited evidence rather than model judgment alone.

The first production target is the expensive template error where rent was drafted as a figure per display face when the intended deal was a total. Redline is built for local review workflows: you point it at a PDF, it cites the source text it used, and the active review profile decides whether the check holds.

## Supported Profiles

Today Redline ships two deterministic lease profiles:

- `lease-general` is the default. It checks commercial lease financials, dates, comparison terms, general clause coverage, renewal notice windows, additional rent/CAM audit visibility, assignment/sublease consent language, and termination-right asymmetry.
- `lease-math` is the narrow billboard/per-display-face lane. It checks rent schedule totals, per-face rent reconciliation, escalation, numeral-vs-words, term dates, and comparison terms.

Non-lease documents such as NDAs, MSAs, and vendor agreements can still be reviewed with advisory context, but Redline does not yet ship deterministic non-lease profiles.

## Install

Install everything with Homebrew:

```bash
brew install --cask chountalas/tap/redline-app
```

That installs `Redline.app` into `/Applications`, installs the Homebrew `python@3.13` runtime dependency, and links `redline` and `redline-mcp` from the engine bundled inside the app. Provider adapters for Codex, Ollama, OpenAI, and Anthropic are included.

The historical CLI-only formula remains available for terminal-only installs, but it is not needed when you install the app cask:

```bash
brew install chountalas/tap/redline
```

Verify the install:

```bash
redline --version
redline --help
```

Upgrade later:

```bash
brew upgrade --cask chountalas/tap/redline-app
```

The Python package is not published to PyPI yet. Homebrew is the supported public install path.

From source for development:

```bash
git clone https://github.com/chountalas/Redline.git
cd Redline
uv sync --extra dev --extra mcp
uv run redline check lease.pdf
```

## Quickstart

```bash
redline check lease.pdf
```

That runs the default `lease-general` profile. Use the narrow math lane when you only want the original billboard/per-display-face checks:

```bash
redline check lease.pdf --profile lease-math
```

Codex subscription is the default provider. It uses your local `codex` CLI login and does not require an API key:

```bash
redline check lease.pdf --provider codex
```

OpenAI API is separate and requires an API key plus an explicit current model:

```bash
export OPENAI_API_KEY=...
redline check lease.pdf --provider openai --model <openai-model>
```

Local Ollama runs do not require an API key:

```bash
ollama pull gpt-oss:20b
redline check lease.pdf --provider ollama --model gpt-oss:20b --base-url http://localhost:11434
```

Anthropic is available only when explicitly selected with an API key plus an explicit current model:

```bash
export ANTHROPIC_API_KEY=...
redline check lease.pdf --provider anthropic --model <anthropic-model>
```

Strict CI mode fails when a rule could not verify:

```bash
redline check lease.pdf --fail-on verify
```

JSON output:

```bash
redline check lease.pdf --json
```

Draft-vs-deal validation:

```bash
redline check lease.pdf --deal deal.yaml
```

Optional AI advisory focus, kept separate from deterministic findings:

```bash
redline check lease.pdf --context "Check that the rent matches the negotiated total economics."
```

For longer review notes, playbooks, approval constraints, or pasted email context, prefer a context file:

```bash
redline check lease.pdf --context-file review-context.md
```

`--thread thread.txt` also accepts review context. For lease profiles it distills supported numeric comparison terms for deterministic checks and keeps qualitative commitments as advisory watch items.

## Mac App

Redline includes a SwiftUI macOS wrapper. The release app bundles the same Python validator engine used by the CLI.

```bash
brew install --cask chountalas/tap/redline-app
```

To install a development build into `/Applications` from a source checkout:

```bash
./script/build_and_run.sh --install
```

The app supports choosing or dropping a PDF, choosing a review profile, choosing an optional comparison sheet, entering optional comparison context/focus text, choosing Codex/OpenAI/Ollama/Anthropic, and reviewing the resulting report from a native window. The API key field is runtime-only and is passed to the CLI process as `REDLINE_API_KEY`; it is not written to disk by Redline. Codex and Ollama do not need a key.

## Screenshots

![Redline empty state](docs/assets/redline-empty-state.png)

## Per-Face Total Demo

Synthetic fixture:

```yaml
total_rent:
  amount: "400000"
  currency: CAD
num_display_faces: 2
```

If the lease says `$400,000 per Display Face` and also states total rent as `$400,000`, Redline emits:

```text
ERROR
- [R2_per_face_total_reconcile] Per-face rent does not reconcile to stated total
  Expected: CAD 800,000.00
  Actual: CAD 400,000.00
```

That is the core trust boundary: the selected model extracts the facts and source quotes; Redline decides whether the math holds.

## What Redline Checks

- `R1_schedule_sums_to_total`: rent schedule sums to stated total.
- `R2_per_face_total_reconcile`: per-face rent times display faces matches stated total.
- `R3_escalation_consistency`: schedule agrees with escalation clauses.
- `R4_numeral_vs_words`: numerals match spelled-out money.
- `R5_term_date_coherence`: commencement, base term, and expiry agree.
- `R6_dealsheet_match`: optional `deal.yaml` matches extracted facts.
- `R7_general_lease_clause_coverage`: general lease clauses are visible enough to review.
- `R8_renewal_notice_window`: renewal options include an extracted notice deadline.
- `R9_additional_rent_audit_visibility`: additional rent/CAM terms have visible audit/review rights.
- `R10_assignment_consent_standard`: assignment/sublease consent is flagged when broadly discretionary.
- `R11_termination_rights_asymmetry`: termination rights are flagged when extracted text appears one-sided.

See [docs/rules.md](docs/rules.md), [docs/dealsheet.md](docs/dealsheet.md), [docs/providers.md](docs/providers.md), [docs/mcp.md](docs/mcp.md), and [docs/mac-app.md](docs/mac-app.md).

## Privacy and Security

Do not commit real documents. The repository should only contain synthetic fixtures. Redline sends extracted document text to the selected provider unless you use local Ollama. Use remote providers only where outbound API processing is acceptable.

Redline is not a law firm and does not provide legal advice. It is a validation tool for lease math, review context, dates, extracted facts, and cited evidence.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

Before public push:

```bash
uv run python scripts/check_release_safety.py
```

## Status

Open-source alpha. Homebrew is the supported public install path. The Python package is not published to PyPI yet.
