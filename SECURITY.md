# Security

## Reporting a Vulnerability

Please open a private security advisory on GitHub or contact the repository owner directly. Do not file public issues containing secrets, real documents, API keys, private review context, or private deal terms.

## Secret Handling

Redline supports API keys through environment variables and runtime app input. Keys must not be committed, written to fixtures, or stored in app snapshots.

Before publishing or pushing a release branch, run:

```bash
uv run python scripts/check_release_safety.py
```

This scanner is a guardrail, not a substitute for review. Also inspect staged files manually for real documents, review context, screenshots, exported reports, and private workflow artifacts.

## Supported Versions

The project is currently in open-source alpha. Security fixes target the latest `main` branch until versioned releases begin.
