from claude_loadtest.metrics import RequestMetric, percentile, summarize


def test_percentile_empty_is_zero():
    assert percentile([], 95) == 0.0


def test_summarize_counts_success_failure_status_and_errors():
    metrics = [
        RequestMetric(index=0, ok=True, status_code=200, latency_ms=100, input_tokens=5, output_tokens=7),
        RequestMetric(index=1, ok=False, status_code=429, latency_ms=300, error="rate_limit_error"),
    ]

    summary = summarize(metrics, elapsed_seconds=2)

    assert summary.total_requests == 2
    assert summary.success_count == 1
    assert summary.failure_count == 1
    assert summary.rps == 1
    assert summary.avg_ms == 200
    assert summary.p95_ms == 300
    assert summary.input_tokens == 5
    assert summary.output_tokens == 7
    assert summary.status_codes == {"200": 1, "429": 1}
    assert summary.errors == {"rate_limit_error": 1}
