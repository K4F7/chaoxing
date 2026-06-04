"""Configuration models and helpers for Claude API load tests."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import json
import os
from typing import Any

DEFAULT_BASE_URL = "https://api.anthropic.com"
DEFAULT_MESSAGES_PATH = "/v1/messages"
DEFAULT_ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MODEL = "claude-sonnet-4-5"
DEFAULT_PROMPT = "Reply with exactly one short sentence for a load-test health check."


@dataclass(slots=True)
class LoadTestConfig:
    """Runtime settings for a Claude Messages API load test."""

    api_key: str
    model: str = DEFAULT_MODEL
    prompt: str = DEFAULT_PROMPT
    base_url: str = DEFAULT_BASE_URL
    path: str = DEFAULT_MESSAGES_PATH
    anthropic_version: str = DEFAULT_ANTHROPIC_VERSION
    total_requests: int = 10
    concurrency: int = 2
    max_tokens: int = 64
    timeout_seconds: float = 60.0
    request_interval_seconds: float = 0.0
    extra_headers: dict[str, str] = field(default_factory=dict)

    @property
    def endpoint(self) -> str:
        """Return the fully-qualified Messages API endpoint."""
        return f"{self.base_url.rstrip('/')}/{self.path.lstrip('/')}"

    def validate(self) -> None:
        """Validate common configuration mistakes before traffic starts."""
        if not self.api_key:
            raise ValueError("api_key is required; set ANTHROPIC_API_KEY or pass --api-key")
        if self.total_requests < 1:
            raise ValueError("total_requests must be at least 1")
        if self.concurrency < 1:
            raise ValueError("concurrency must be at least 1")
        if self.max_tokens < 1:
            raise ValueError("max_tokens must be at least 1")
        if self.timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        if self.request_interval_seconds < 0:
            raise ValueError("request_interval_seconds cannot be negative")


def load_config_file(path: str | Path) -> dict[str, Any]:
    """Load a JSON configuration file."""
    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("config file must contain a JSON object")
    return data


def build_config(overrides: dict[str, Any]) -> LoadTestConfig:
    """Build a validated config from CLI/file overrides and environment variables."""
    data = dict(overrides)
    api_key = data.pop("api_key", None) or os.getenv("ANTHROPIC_API_KEY", "")
    config = LoadTestConfig(api_key=api_key, **{k: v for k, v in data.items() if v is not None})
    config.validate()
    return config
