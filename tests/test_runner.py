import pytest
import respx
from httpx import Response

from claude_loadtest.config import LoadTestConfig
from claude_loadtest.runner import run_load_test


@pytest.mark.asyncio
@respx.mock
async def test_run_load_test_collects_success_metrics():
    route = respx.post("https://api.anthropic.com/v1/messages").mock(
        return_value=Response(
            200,
            json={
                "id": "msg_123",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "text", "text": "ok"}],
                "model": "claude-sonnet-4-5",
                "stop_reason": "end_turn",
                "usage": {"input_tokens": 10, "output_tokens": 3},
            },
        )
    )
    config = LoadTestConfig(api_key="test-key", total_requests=3, concurrency=2)

    result = await run_load_test(config)

    assert route.call_count == 3
    assert result.summary.total_requests == 3
    assert result.summary.success_count == 3
    assert result.summary.failure_count == 0
    assert result.summary.input_tokens == 30
    assert result.summary.output_tokens == 9


@pytest.mark.asyncio
@respx.mock
async def test_run_load_test_records_api_errors():
    respx.post("https://api.anthropic.com/v1/messages").mock(
        return_value=Response(429, json={"error": {"type": "rate_limit_error"}})
    )
    config = LoadTestConfig(api_key="test-key", total_requests=1, concurrency=1)

    result = await run_load_test(config)

    assert result.summary.failure_count == 1
    assert result.summary.status_codes == {"429": 1}
    assert result.summary.errors == {"rate_limit_error": 1}
