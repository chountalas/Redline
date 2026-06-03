from __future__ import annotations

import json
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal, cast
from urllib import error, request

from pydantic import BaseModel

from redline.errors import ExtractionError

Provider = Literal["codex", "openai", "ollama", "anthropic"]

DEFAULT_PROVIDER: Provider = "codex"
DEFAULT_OLLAMA_MODEL = "gpt-oss:20b"
DEFAULT_OLLAMA_BASE_URL = "http://localhost:11434"
DEFAULT_OLLAMA_TIMEOUT = 600.0

# Regex lookaround tokens that strict structured-output validators reject.
_LOOKAROUND_TOKENS = ("(?=", "(?!", "(?<=", "(?<!")


@dataclass(frozen=True)
class LLMConfig:
    provider: Provider = DEFAULT_PROVIDER
    model: str | None = None
    api_key: str | None = None
    base_url: str | None = None

    @classmethod
    def from_options(
        cls,
        *,
        provider: str | None = None,
        model: str | None = None,
        api_key: str | None = None,
        base_url: str | None = None,
    ) -> LLMConfig:
        resolved_provider = _resolve_provider(provider)
        return cls(
            provider=resolved_provider,
            model=model or _env_model(resolved_provider),
            api_key=api_key or os.getenv("REDLINE_API_KEY") or _env_api_key(resolved_provider),
            base_url=base_url or _env_base_url(resolved_provider),
        )

    @property
    def resolved_model(self) -> str:
        if self.model:
            return self.model
        if self.provider == "codex":
            return ""
        if self.provider == "ollama":
            return DEFAULT_OLLAMA_MODEL
        raise ExtractionError(
            f"--model or REDLINE_{self.provider.upper()}_MODEL is required "
            f"for provider={self.provider}."
        )


def complete_structured(
    *,
    config: LLMConfig,
    system: str,
    prompt: str,
    schema_name: str,
    schema: dict[str, Any],
    max_output_tokens: int,
) -> dict[str, Any]:
    if config.provider == "codex":
        return _complete_codex(
            config=config,
            system=system,
            prompt=prompt,
            schema_name=schema_name,
            schema=schema,
        )
    if config.provider == "openai":
        return _complete_openai(
            config=config,
            system=system,
            prompt=prompt,
            schema_name=schema_name,
            schema=schema,
            max_output_tokens=max_output_tokens,
        )
    if config.provider == "ollama":
        return _complete_ollama(
            config=config,
            system=system,
            prompt=prompt,
            schema=schema,
        )
    if config.provider == "anthropic":
        return _complete_anthropic(
            config=config,
            system=system,
            prompt=prompt,
            schema_name=schema_name,
            schema=schema,
            max_output_tokens=max_output_tokens,
        )
    raise ExtractionError(f"Unsupported provider: {config.provider}")


def strict_model_schema(model: type[BaseModel]) -> dict[str, Any]:
    schema = model.model_json_schema()
    _force_strict_objects(schema)
    return schema


def strict_object_schema(schema: dict[str, Any]) -> dict[str, Any]:
    copied = json.loads(json.dumps(schema))
    _force_strict_objects(copied)
    return cast(dict[str, Any], copied)


def _resolve_provider(provider: str | None) -> Provider:
    raw = (provider or os.getenv("REDLINE_LLM_PROVIDER") or DEFAULT_PROVIDER).lower().strip()
    if raw in {"codex", "openai", "ollama", "anthropic"}:
        return cast(Provider, raw)
    raise ExtractionError("Provider must be one of: codex, openai, ollama, anthropic.")


def _env_model(provider: Provider) -> str | None:
    provider_key = provider.upper()
    return (
        os.getenv("REDLINE_MODEL")
        or os.getenv(f"REDLINE_{provider_key}_MODEL")
    )


def _env_api_key(provider: Provider) -> str | None:
    if provider == "openai":
        return os.getenv("OPENAI_API_KEY")
    if provider == "anthropic":
        return os.getenv("ANTHROPIC_API_KEY")
    return None


def _env_base_url(provider: Provider) -> str | None:
    provider_key = provider.upper()
    return os.getenv("REDLINE_BASE_URL") or os.getenv(f"REDLINE_{provider_key}_BASE_URL")


def _ollama_timeout() -> float:
    raw = os.getenv("REDLINE_OLLAMA_TIMEOUT")
    if raw:
        try:
            value = float(raw)
        except ValueError:
            value = 0.0
        if value > 0:
            return value
    return DEFAULT_OLLAMA_TIMEOUT


def _ollama_format(schema: dict[str, Any]) -> dict[str, Any] | str:
    # Default to Ollama's lightweight JSON mode. Binding the full JSON Schema as a
    # grammar (REDLINE_OLLAMA_FORMAT=schema) guarantees field names, but local
    # models under that grammar routinely run away on the unbounded arrays and
    # never terminate. JSON mode terminates fast; the prompt carries the exact
    # shape and the extractor's retry loop repairs any field drift.
    if (os.getenv("REDLINE_OLLAMA_FORMAT") or "json").lower().strip() == "schema":
        return schema
    return "json"


def _complete_openai(
    *,
    config: LLMConfig,
    system: str,
    prompt: str,
    schema_name: str,
    schema: dict[str, Any],
    max_output_tokens: int,
) -> dict[str, Any]:
    api_key = config.api_key
    if not api_key:
        raise ExtractionError("OPENAI_API_KEY or REDLINE_API_KEY is required for provider=openai.")

    client = _create_openai_client(api_key=api_key, base_url=config.base_url)
    response = client.responses.create(
        model=config.resolved_model,
        input=[
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        max_output_tokens=max_output_tokens,
        text={
            "format": {
                "type": "json_schema",
                "name": schema_name,
                "strict": True,
                "schema": schema,
            }
        },
    )
    return _loads_json_object(_openai_response_text(response))


def _complete_codex(
    *,
    config: LLMConfig,
    system: str,
    prompt: str,
    schema_name: str,
    schema: dict[str, Any],
) -> dict[str, Any]:
    codex_binary = config.base_url or os.getenv("REDLINE_CODEX_COMMAND") or "codex"
    with tempfile.TemporaryDirectory(prefix="redline-codex-") as tmpdir:
        tmp_path = Path(tmpdir)
        schema_path = tmp_path / f"{schema_name}.schema.json"
        output_path = tmp_path / f"{schema_name}.output.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")

        command = [
            codex_binary,
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--ignore-rules",
            "--sandbox",
            "read-only",
            "--output-schema",
            str(schema_path),
            "--output-last-message",
            str(output_path),
        ]
        if config.model:
            command.extend(["--model", config.model])
        command.append("-")

        combined_prompt = (
            f"{system}\n\n"
            f"{prompt}\n\n"
            "Return only the structured JSON object matching the supplied output schema."
        )
        try:
            result = subprocess.run(
                command,
                input=combined_prompt,
                text=True,
                capture_output=True,
                timeout=180,
                check=False,
            )
        except FileNotFoundError as exc:
            raise ExtractionError(
                "Codex CLI was not found. Install/login to Codex or choose another provider."
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise ExtractionError("Codex CLI extraction timed out.") from exc

        if result.returncode != 0:
            stderr = result.stderr.strip()
            stdout = result.stdout.strip()
            detail = stderr or stdout or f"exit code {result.returncode}"
            raise ExtractionError(f"Codex CLI extraction failed: {detail}")

        output = output_path.read_text(encoding="utf-8") if output_path.exists() else result.stdout
        return _loads_json_object(output)


def _complete_ollama(
    *,
    config: LLMConfig,
    system: str,
    prompt: str,
    schema: dict[str, Any],
) -> dict[str, Any]:
    base_url = (config.base_url or DEFAULT_OLLAMA_BASE_URL).rstrip("/")
    payload = {
        "model": config.resolved_model,
        "stream": False,
        "format": _ollama_format(schema),
        # Disable chain-of-thought: on hybrid reasoning models (e.g. qwen3) the
        # thinking tokens blow the time budget and, in JSON mode, crowd out the
        # actual JSON. A no-op for non-reasoning models. Structured extraction
        # wants the answer, not the reasoning.
        "think": False,
        "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(
        f"{base_url}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    timeout = _ollama_timeout()
    timed_out_message = (
        f"Ollama request timed out after {timeout:g}s. Larger local models can be slow; "
        "raise REDLINE_OLLAMA_TIMEOUT (seconds) to allow more time."
    )
    try:
        with request.urlopen(req, timeout=timeout) as response:
            response_body = response.read().decode("utf-8")
    except TimeoutError as exc:
        raise ExtractionError(timed_out_message) from exc
    except error.URLError as exc:
        if isinstance(getattr(exc, "reason", exc), TimeoutError):
            raise ExtractionError(timed_out_message) from exc
        raise ExtractionError(f"Ollama request failed: {exc}") from exc

    raw = _loads_json_object(response_body)
    message = raw.get("message")
    content = message.get("content") if isinstance(message, dict) else raw.get("response")
    if not isinstance(content, str) or not content.strip():
        raise ExtractionError("Ollama response did not contain structured content.")
    return _loads_json_object(content)


def _complete_anthropic(
    *,
    config: LLMConfig,
    system: str,
    prompt: str,
    schema_name: str,
    schema: dict[str, Any],
    max_output_tokens: int,
) -> dict[str, Any]:
    api_key = config.api_key
    if not api_key:
        raise ExtractionError(
            "ANTHROPIC_API_KEY or REDLINE_API_KEY is required for provider=anthropic."
        )

    client = _create_anthropic_client(api_key)
    response = client.messages.create(
        model=config.resolved_model,
        max_tokens=max_output_tokens,
        temperature=0,
        system=system,
        messages=[{"role": "user", "content": prompt}],
        tools=[
            {
                "name": schema_name,
                "description": "Return structured Redline extraction output.",
                "input_schema": schema,
                "strict": True,
            }
        ],
        tool_choice={"type": "tool", "name": schema_name},
    )
    return _anthropic_tool_input(response, schema_name)


def _create_openai_client(*, api_key: str, base_url: str | None = None) -> Any:
    try:
        from openai import OpenAI
    except ImportError as exc:  # pragma: no cover
        raise ExtractionError("The openai package is required for provider=openai.") from exc

    if base_url:
        return OpenAI(api_key=api_key, base_url=base_url)
    return OpenAI(api_key=api_key)


def _create_anthropic_client(api_key: str) -> Any:
    try:
        from anthropic import Anthropic
    except ImportError as exc:  # pragma: no cover
        raise ExtractionError(
            "Install Anthropic support with: pip install 'redline-lease[anthropic]'"
        ) from exc
    return Anthropic(api_key=api_key)


def _openai_response_text(response: Any) -> str:
    output_text = getattr(response, "output_text", None)
    if isinstance(output_text, str) and output_text.strip():
        return output_text

    chunks: list[str] = []
    for output in getattr(response, "output", []):
        for item in getattr(output, "content", []):
            text = getattr(item, "text", None)
            if text:
                chunks.append(text)
    if chunks:
        return "\n".join(chunks)
    raise ExtractionError("OpenAI response did not contain text output.")


def _anthropic_tool_input(response: Any, expected_tool_name: str) -> dict[str, Any]:
    for block in getattr(response, "content", []):
        block_type = getattr(block, "type", None)
        block_name = getattr(block, "name", None)
        if block_type == "tool_use" and block_name == expected_tool_name:
            raw_input = getattr(block, "input", None)
            if not isinstance(raw_input, dict):
                raise ExtractionError(f"{expected_tool_name} input must be a JSON object.")
            return cast(dict[str, Any], raw_input)
    raise ExtractionError(f"Model did not return the required tool output: {expected_tool_name}.")


def _loads_json_object(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if not stripped.startswith("{"):
        start = stripped.find("{")
        end = stripped.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise ExtractionError("No JSON object found in model response.")
        stripped = stripped[start : end + 1]
    try:
        raw: Any = json.loads(stripped)
    except json.JSONDecodeError as exc:
        raise ExtractionError(f"Invalid JSON: {exc}") from exc
    if not isinstance(raw, dict):
        raise ExtractionError("Model response must be a JSON object.")
    return raw


def _force_strict_objects(schema: dict[str, Any]) -> None:
    pattern = schema.get("pattern")
    if isinstance(pattern, str) and any(token in pattern for token in _LOOKAROUND_TOKENS):
        # OpenAI/Codex strict structured output cannot compile regex lookaround,
        # and llama.cpp (Ollama) grammars choke on it too. Pydantic emits such a
        # pattern for Decimal fields; the value is re-validated by the model
        # parsers on the way in, so the JSON-schema pattern is safe to drop.
        del schema["pattern"]

    if schema.get("type") == "object" or "properties" in schema:
        properties = schema.get("properties")
        if isinstance(properties, dict):
            schema["additionalProperties"] = False
            schema["required"] = list(properties.keys())
            for value in properties.values():
                if isinstance(value, dict):
                    _force_strict_objects(value)

    defs = schema.get("$defs")
    if isinstance(defs, dict):
        for value in defs.values():
            if isinstance(value, dict):
                _force_strict_objects(value)

    items = schema.get("items")
    if isinstance(items, dict):
        _force_strict_objects(items)

    for keyword in ("anyOf", "oneOf", "allOf"):
        variants = schema.get(keyword)
        if isinstance(variants, list):
            for variant in variants:
                if isinstance(variant, dict):
                    _force_strict_objects(variant)
