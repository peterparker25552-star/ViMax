from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

from openai import APIConnectionError, APITimeoutError, AsyncOpenAI, RateLimitError

from .config import llm_api_key, llm_base_url, llm_model, llm_reasoning_effort
from .models import ToolCall


LLM_MAX_ATTEMPTS = 3
LLM_RETRY_BACKOFF_SECONDS = (1.0, 4.0)
LLM_REQUEST_TIMEOUT_SECONDS = 300.0
# Rate limits need far more patience than transient errors: free tiers reset
# per-minute (or daily) quotas, and providers say how long via Retry-After.
RATE_LIMIT_MAX_ATTEMPTS = 5
RATE_LIMIT_BACKOFF_SECONDS = (5.0, 15.0, 30.0, 60.0, 90.0)


def _is_rate_limit_error(exc: BaseException) -> bool:
    if isinstance(exc, RateLimitError):
        return True
    status = getattr(exc, "status_code", None)
    try:
        return status is not None and int(status) == 429
    except (TypeError, ValueError):
        return False


def _retry_after_seconds(exc: BaseException) -> float | None:
    """Retry-After header from the provider, clamped to 1-120 seconds."""
    response = getattr(exc, "response", None)
    headers = getattr(response, "headers", None)
    if headers is None:
        return None
    try:
        value = headers.get("retry-after")
    except Exception:
        return None
    if not value:
        return None
    try:
        return max(1.0, min(120.0, float(value)))
    except (TypeError, ValueError):
        return None


def _is_reasoning_effort_rejection(exc: BaseException) -> bool:
    """True when the provider answered 400 specifically about reasoning_effort."""
    status = getattr(exc, "status_code", None)
    if status is not None:
        try:
            status = int(status)
        except (TypeError, ValueError):
            return False
        if status != 400:
            return False
    text = str(exc).lower()
    return "reasoning_effort" in text or "reasoning effort" in text


def _is_retryable_llm_error(exc: BaseException) -> bool:
    status = getattr(exc, "status_code", None)
    if status is not None:
        try:
            status = int(status)
        except (TypeError, ValueError):
            return False
        return status == 429 or status >= 500
    return isinstance(exc, (APIConnectionError, APITimeoutError))


class LLMResponseShapeError(RuntimeError):
    pass


@dataclass(slots=True)
class AssistantMessage:
    text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    raw_message: dict[str, Any] = field(default_factory=dict)


class OpenAICompatibleLLM:
    def __init__(self, model: str | None = None, base_url: str | None = None, api_key: str | None = None) -> None:
        self.model = model or llm_model()
        self.base_url = base_url or llm_base_url()
        self.api_key = api_key or llm_api_key()
        if not self.api_key:
            raise RuntimeError("VIMAX_LLM_API_KEY is required for the agent LLM client")
        self.client = AsyncOpenAI(api_key=self.api_key, base_url=self.base_url, timeout=LLM_REQUEST_TIMEOUT_SECONDS)
        # Optional reasoning control for thinking models (e.g. Gemini 3.x):
        # 'low' cuts 30-60s of hidden reasoning to a few seconds. Dropped
        # automatically if the provider rejects the parameter.
        self.reasoning_effort = (llm_reasoning_effort() or "").strip().lower() or None

    async def complete(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]]) -> AssistantMessage:
        shape_attempts = [
            {"tools": tools or None, "tool_choice": "auto" if tools else None},
            {"tools": tools or None, "tool_choice": "auto" if tools else None},
        ]
        if tools:
            shape_attempts.append({"tools": None, "tool_choice": None})

        last_shape_error: Exception | None = None
        for attempt in shape_attempts:
            try:
                response = await self._create_completion_with_retries(messages, attempt["tools"], attempt["tool_choice"])
                return _assistant_message_from_response(response)
            except LLMResponseShapeError as exc:
                last_shape_error = exc
                continue
        assert last_shape_error is not None
        raise last_shape_error

    async def _create_completion_with_retries(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None, tool_choice: str | None) -> Any:
        attempt = 0
        rate_limit_attempts = 0
        while True:
            try:
                return await self._create_completion(messages, tools, tool_choice)
            except Exception as exc:
                if isinstance(exc, LLMResponseShapeError):
                    raise
                if _is_rate_limit_error(exc):
                    rate_limit_attempts += 1
                    if rate_limit_attempts > RATE_LIMIT_MAX_ATTEMPTS:
                        raise
                    delay = _retry_after_seconds(exc) or RATE_LIMIT_BACKOFF_SECONDS[
                        min(rate_limit_attempts - 1, len(RATE_LIMIT_BACKOFF_SECONDS) - 1)
                    ]
                    logging.warning(
                        "LLM rate limited by the provider; waiting %.0fs before retry (%d/%d). "
                        "Free tiers reset per-minute quotas — this resolves itself.",
                        delay, rate_limit_attempts, RATE_LIMIT_MAX_ATTEMPTS,
                    )
                    await asyncio.sleep(delay)
                    continue
                attempt += 1
                if attempt >= LLM_MAX_ATTEMPTS or not _is_retryable_llm_error(exc):
                    raise
                delay = LLM_RETRY_BACKOFF_SECONDS[min(attempt - 1, len(LLM_RETRY_BACKOFF_SECONDS) - 1)]
                logging.warning("LLM call failed (%s); retrying in %.1fs (attempt %d/%d)", exc, delay, attempt, LLM_MAX_ATTEMPTS)
                await asyncio.sleep(delay)

    async def _create_completion(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]] | None, tool_choice: str | None) -> Any:
        kwargs: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
        }
        if tools:
            kwargs["tools"] = tools
        if tool_choice:
            kwargs["tool_choice"] = tool_choice
        if self.reasoning_effort:
            kwargs["reasoning_effort"] = self.reasoning_effort
        try:
            return await self.client.chat.completions.create(**kwargs)
        except Exception as exc:
            if self.reasoning_effort and _is_reasoning_effort_rejection(exc):
                logging.warning("Provider rejected reasoning_effort=%r; continuing without it", self.reasoning_effort)
                self.reasoning_effort = None
                kwargs.pop("reasoning_effort", None)
                return await self.client.chat.completions.create(**kwargs)
            raise


def _assistant_message_from_response(response: Any) -> AssistantMessage:
    message = _extract_message(response)
    text = _message_value(message, "content") or ""
    calls: list[ToolCall] = []
    for call in _message_value(message, "tool_calls") or []:
        function = _message_value(call, "function") or {}
        try:
            arguments = json.loads(_message_value(function, "arguments") or "{}")
        except json.JSONDecodeError:
            arguments = {}
        calls.append(ToolCall(id=_message_value(call, "id") or f"tool-{uuid4().hex[:12]}", name=_message_value(function, "name"), arguments=arguments))
    return AssistantMessage(text=text, tool_calls=calls, raw_message=_dump_message(message))


def _extract_message(response: Any) -> Any:
    if isinstance(response, str):
        try:
            response = json.loads(response)
        except json.JSONDecodeError as exc:
            raise LLMResponseShapeError(f"LLM provider returned a string instead of a chat completion object: {response[:300]}") from exc
    choices = _message_value(response, "choices")
    if not choices:
        raise LLMResponseShapeError(f"LLM provider response missing choices: {str(response)[:500]}")
    first_choice = choices[0]
    message = _message_value(first_choice, "message")
    if message is None:
        raise LLMResponseShapeError(f"LLM provider response missing choice.message: {str(response)[:500]}")
    return message


def _message_value(obj: Any, key: str) -> Any:
    if isinstance(obj, dict):
        return obj.get(key)
    return getattr(obj, key, None)


def _dump_message(message: Any) -> dict[str, Any]:
    if isinstance(message, dict):
        return message
    if hasattr(message, "model_dump"):
        return message.model_dump()
    return {"content": str(message)}
