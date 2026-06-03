from __future__ import annotations

import json
import subprocess
from types import SimpleNamespace
from typing import Any

import pytest

from redline.errors import ExtractionError
from redline.llm import (
    LLMConfig,
    complete_structured,
    strict_model_schema,
    strict_object_schema,
)
from redline.models import LeaseFacts

_LOOKAROUND = ("(?=", "(?!", "(?<=", "(?<!")
_OK_SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"]}


def test_strict_schemas_drop_lookaround_patterns() -> None:
    # OpenAI/Codex strict structured output rejects regex lookaround; Pydantic
    # emits such a pattern for Decimal fields. Both strict-schema entry points
    # must strip it.
    model_schema = json.dumps(strict_model_schema(LeaseFacts))
    assert not any(token in model_schema for token in _LOOKAROUND)

    object_schema = json.dumps(
        strict_object_schema(
            {
                "type": "object",
                "properties": {"n": {"type": "string", "pattern": "^(?!x)\\d+$"}},
                "required": ["n"],
            }
        )
    )
    assert not any(token in object_schema for token in _LOOKAROUND)


class FakeHTTPResponse:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    def __enter__(self) -> FakeHTTPResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


def _fake_ollama(monkeypatch: pytest.MonkeyPatch, requests: list[Any]) -> None:
    def fake_urlopen(req: Any, timeout: int) -> FakeHTTPResponse:
        requests.append((req, timeout))
        return FakeHTTPResponse({"message": {"content": json.dumps({"ok": True})}})

    monkeypatch.setattr("redline.llm.request.urlopen", fake_urlopen)


def test_ollama_provider_uses_json_mode_by_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("REDLINE_OLLAMA_FORMAT", raising=False)
    requests: list[Any] = []
    _fake_ollama(monkeypatch, requests)

    result = complete_structured(
        config=LLMConfig(provider="ollama", model="llama3.1", base_url="http://local.test"),
        system="system",
        prompt="prompt",
        schema_name="test_schema",
        schema=_OK_SCHEMA,
        max_output_tokens=100,
    )

    body = json.loads(requests[0][0].data.decode("utf-8"))
    assert requests[0][0].full_url == "http://local.test/api/chat"
    assert body["model"] == "llama3.1"
    assert body["stream"] is False
    # Default is Ollama's lightweight JSON mode (not the heavy schema grammar),
    # which terminates quickly on local models.
    assert body["format"] == "json"
    assert result == {"ok": True}


def test_ollama_provider_sends_schema_when_opted_in(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("REDLINE_OLLAMA_FORMAT", "schema")
    requests: list[Any] = []
    _fake_ollama(monkeypatch, requests)

    complete_structured(
        config=LLMConfig(provider="ollama", model="llama3.1", base_url="http://local.test"),
        system="system",
        prompt="prompt",
        schema_name="test_schema",
        schema=_OK_SCHEMA,
        max_output_tokens=100,
    )

    body = json.loads(requests[0][0].data.decode("utf-8"))
    assert body["format"]["properties"]["ok"]["type"] == "boolean"


def test_ollama_timeout_raises_clean_extraction_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("REDLINE_OLLAMA_TIMEOUT", "5")

    def fake_urlopen(req: Any, timeout: int) -> FakeHTTPResponse:
        raise TimeoutError("timed out")

    monkeypatch.setattr("redline.llm.request.urlopen", fake_urlopen)

    with pytest.raises(ExtractionError) as excinfo:
        complete_structured(
            config=LLMConfig(provider="ollama", model="llama3.1", base_url="http://local.test"),
            system="system",
            prompt="prompt",
            schema_name="test_schema",
            schema=_OK_SCHEMA,
            max_output_tokens=100,
        )

    message = str(excinfo.value)
    assert "timed out after 5s" in message
    assert "REDLINE_OLLAMA_TIMEOUT" in message


def test_codex_provider_uses_cli_output_schema_without_default_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = []

    def fake_run(
        command: list[str],
        input: str,
        text: bool,
        capture_output: bool,
        timeout: int,
        check: bool,
    ) -> subprocess.CompletedProcess[str]:
        del input, text, capture_output, timeout, check
        calls.append(command)
        output_path = command[command.index("--output-last-message") + 1]
        with open(output_path, "w", encoding="utf-8") as handle:
            json.dump({"ok": True}, handle)
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("redline.llm.subprocess.run", fake_run)

    result = complete_structured(
        config=LLMConfig(provider="codex"),
        system="system",
        prompt="prompt",
        schema_name="test_schema",
        schema=_OK_SCHEMA,
        max_output_tokens=100,
    )

    assert calls[0][:2] == ["codex", "exec"]
    assert "--output-schema" in calls[0]
    assert "--output-last-message" in calls[0]
    assert "--model" not in calls[0]
    assert "--ask-for-approval" not in calls[0]
    assert result == {"ok": True}


def test_codex_provider_respects_explicit_model(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = []

    def fake_run(
        command: list[str],
        input: str,
        text: bool,
        capture_output: bool,
        timeout: int,
        check: bool,
    ) -> subprocess.CompletedProcess[str]:
        del input, text, capture_output, timeout, check
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout='{"ok": true}', stderr="")

    monkeypatch.setattr("redline.llm.subprocess.run", fake_run)

    complete_structured(
        config=LLMConfig(provider="codex", model="codex-test-model"),
        system="system",
        prompt="prompt",
        schema_name="test_schema",
        schema=_OK_SCHEMA,
        max_output_tokens=100,
    )

    assert calls[0][calls[0].index("--model") + 1] == "codex-test-model"


def test_openai_provider_requires_explicit_model(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REDLINE_MODEL", raising=False)
    monkeypatch.delenv("REDLINE_OPENAI_MODEL", raising=False)

    with pytest.raises(ExtractionError, match="provider=openai"):
        complete_structured(
            config=LLMConfig(provider="openai", api_key="redline-key"),
            system="system",
            prompt="prompt",
            schema_name="test_schema",
            schema=_OK_SCHEMA,
            max_output_tokens=100,
        )


def test_anthropic_provider_requires_explicit_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REDLINE_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)

    with pytest.raises(ExtractionError, match="provider=anthropic"):
        complete_structured(
            config=LLMConfig(provider="anthropic"),
            system="system",
            prompt="prompt",
            schema_name="test_schema",
            schema={"type": "object", "properties": {}},
            max_output_tokens=100,
        )


def test_openai_provider_uses_generic_redline_api_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = []

    class FakeResponses:
        def create(self, **kwargs: Any) -> SimpleNamespace:
            calls.append(kwargs)
            return SimpleNamespace(output_text=json.dumps({"ok": True}))

    class FakeClient:
        responses = FakeResponses()

    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: FakeClient(),
    )

    result = complete_structured(
        config=LLMConfig(provider="openai", model="openai-test-model", api_key="redline-key"),
        system="system",
        prompt="prompt",
        schema_name="test_schema",
        schema=_OK_SCHEMA,
        max_output_tokens=100,
    )

    assert calls[0]["model"] == "openai-test-model"
    assert calls[0]["text"]["format"]["strict"] is True
    assert result == {"ok": True}


def test_legacy_claude_model_env_does_not_affect_openai(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("REDLINE_CLAUDE_MODEL", "legacy-claude-model")
    monkeypatch.delenv("REDLINE_MODEL", raising=False)
    monkeypatch.delenv("REDLINE_OPENAI_MODEL", raising=False)

    config = LLMConfig.from_options(provider="openai", api_key="test-key")

    with pytest.raises(ExtractionError, match="provider=openai"):
        _ = config.resolved_model


def test_default_provider_is_codex(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REDLINE_LLM_PROVIDER", raising=False)

    config = LLMConfig.from_options()

    assert config.provider == "codex"
    assert config.resolved_model == ""
