import pytest

from claude_loadtest.config import LoadTestConfig, build_config


def test_endpoint_normalizes_slashes():
    config = LoadTestConfig(api_key="test", base_url="https://example.com/", path="/v1/messages")

    assert config.endpoint == "https://example.com/v1/messages"


def test_build_config_reads_api_key_from_environment(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "env-key")

    config = build_config({"total_requests": 3})

    assert config.api_key == "env-key"
    assert config.total_requests == 3


def test_validation_rejects_missing_key(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)

    with pytest.raises(ValueError, match="api_key is required"):
        build_config({})


def test_explicit_api_key_wins(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "env-key")

    config = build_config({"api_key": "cli-key"})

    assert config.api_key == "cli-key"
