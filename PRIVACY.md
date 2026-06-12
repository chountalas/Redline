# Privacy

Redline processes documents, review context, comparison sheets, and exported reports supplied by the user. Do not commit real documents, negotiated terms, exported reports, screenshots, or review context containing confidential terms.

## Local Data

The command-line tool reads input files from the paths you provide and writes output only where you redirect or save it.

The macOS app stores its local library, review flags, notes, and non-secret settings in the user's Application Support directory. API keys are not persisted by Redline.

## Provider Data

Redline sends extracted document text, review context, comparison terms, and prompt context to the selected provider unless you use a local provider such as Ollama.

- `codex`: uses the locally authenticated Codex CLI.
- `openai`: sends data to the OpenAI API.
- `anthropic`: sends data to the Anthropic API when explicitly selected.
- `ollama`: runs against your configured local Ollama server.

Use remote providers only when outbound processing is acceptable for the document and context you are reviewing.

## Fixtures

Repository fixtures and tests must be synthetic. If a fixture resembles a real document, replace names, addresses, financial terms, dates, and private business context with obviously fabricated values before committing.
