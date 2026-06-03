# Contributing

Redline's trust boundary is strict:

```text
LLM extraction -> structured facts
deterministic rules -> verdicts
```

Do not put model judgment inside deterministic rule functions.

## Add a Rule

1. Add a pure function in `src/redline/rules.py`.
2. Return `COULD_NOT_VERIFY` when required facts are missing.
3. Include source evidence from `ExtractedValue`, `ScheduleLine`, or `AmountWordPair`.
4. Register the function in `RULES`.
5. Add fixture-style tests in `tests/test_rules.py`.
6. Document the rule in `docs/rules.md`.

Rules should accept only `LeaseFacts` and optional `DealSheet`, and return `list[Finding]`.

## Test

```bash
uv run pytest
uv run ruff check .
uv run mypy src
```

Tests must use synthetic leases only.

