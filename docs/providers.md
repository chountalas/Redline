# Model Providers

Redline is model-agnostic at the extraction boundary. The model turns document text into structured facts for the active review profile; deterministic Redline rules produce the verdicts. The current production profiles extract commercial lease facts.

## Default: Codex Subscription

Codex is the default provider. It shells out to your local authenticated Codex CLI with a strict output schema.

```bash
redline check lease.pdf
```

Optional model override:

```bash
redline check lease.pdf --provider codex --model <codex-model>
```

If `--model` is omitted, Codex uses your configured/default subscription model.

Environment defaults:

```bash
REDLINE_LLM_PROVIDER=codex
# Optional:
# REDLINE_MODEL=
# REDLINE_CODEX_COMMAND=/opt/homebrew/bin/codex
```

## OpenAI API

OpenAI API is available separately and requires an API key plus an explicit current model. Redline uses HTTPS directly, so no OpenAI Python SDK install is required.

```bash
export OPENAI_API_KEY=...
redline check lease.pdf
```

```bash
redline check lease.pdf --provider openai --model <openai-model>
```

You can set defaults with environment variables:

```bash
REDLINE_LLM_PROVIDER=openai
REDLINE_MODEL=<openai-model>
OPENAI_API_KEY=...
```

## Local: Ollama

Ollama runs locally and does not require an API key.

```bash
ollama pull gpt-oss:20b
redline check lease.pdf --provider ollama --model gpt-oss:20b --base-url http://localhost:11434
```

Any Ollama model can be used, but extraction quality depends heavily on the
model's ability to produce the exact JSON shape. Use a capable instruction model
(e.g. a 20B+ model); tiny models tend to omit facts.

By default Redline uses Ollama's lightweight JSON mode and disables model
"thinking", which keeps generation fast and terminates reliably. Two knobs:

```bash
# Larger local models can take minutes; raise the request timeout (seconds).
export REDLINE_OLLAMA_TIMEOUT=600

# Output mode. "json" (default) is fast and recommended. "schema" binds the
# full JSON-schema grammar; it is stricter about field names but local models
# frequently run away on unbounded arrays and never finish, so only use it on
# fast hardware with a strong model.
export REDLINE_OLLAMA_FORMAT=json
```

Reasoning models (e.g. qwen3) are supported: Redline sends `think: false` so the
model returns JSON directly instead of spending the time/budget on chain-of-thought.

## Optional: Anthropic

Anthropic is not the default provider. Use it only when explicitly selected and an API key plus explicit current model are available. Redline uses HTTPS directly, so no Anthropic Python SDK install is required.

```bash
export ANTHROPIC_API_KEY=...
redline check lease.pdf --provider anthropic --model <anthropic-model>
```

## Common Environment Variables

```bash
REDLINE_LLM_PROVIDER=codex|openai|ollama|anthropic
REDLINE_MODEL=<provider-model>
REDLINE_BASE_URL=<provider-base-url>
REDLINE_API_KEY=<provider-api-key>
```

Provider-specific API keys are also supported:

```bash
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
```
