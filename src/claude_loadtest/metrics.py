"""Metric aggregation helpers for load-test results."""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean
from typing import Iterable


@dataclass(slots=True)
class RequestMetric:
    """Metrics captured for a single request attempt."""

    index: int
    ok: bool
    status_code: int | None
    latency_ms: float
    input_tokens: int = 0
    output_tokens: int = 0
    error: str | None = None


@dataclass(slots=True)
class MetricsSummary:
    """Aggregated load-test metrics."""

    total_requests: int
    success_count: int
    failure_count: int
    rps: float
    min_ms: float
    avg_ms: float
    p50_ms: float
    p90_ms: float
    p95_ms: float
    p99_ms: float
    max_ms: float
    input_tokens: int
    output_tokens: int
    status_codes: dict[str, int] = field(default_factory=dict)
    errors: dict[str, int] = field(default_factory=dict)


def percentile(values: list[float], percent: float) -> float:
    """Return a nearest-rank percentile for already collected values."""
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, round((percent / 100) * (len(ordered) - 1))))
    return ordered[index]


def summarize(metrics: Iterable[RequestMetric], elapsed_seconds: float) -> MetricsSummary:
    """Summarize request metrics into throughput, latency, and error counters."""
    rows = list(metrics)
    latencies = [row.latency_ms for row in rows]
    status_codes: dict[str, int] = {}
    errors: dict[str, int] = {}

    for row in rows:
        if row.status_code is not None:
            key = str(row.status_code)
            status_codes[key] = status_codes.get(key, 0) + 1
        if row.error:
            errors[row.error] = errors.get(row.error, 0) + 1

    success_count = sum(1 for row in rows if row.ok)
    failure_count = len(rows) - success_count
    safe_elapsed = max(elapsed_seconds, 1e-9)

    return MetricsSummary(
        total_requests=len(rows),
        success_count=success_count,
        failure_count=failure_count,
        rps=len(rows) / safe_elapsed,
        min_ms=min(latencies, default=0.0),
        avg_ms=mean(latencies) if latencies else 0.0,
        p50_ms=percentile(latencies, 50),
        p90_ms=percentile(latencies, 90),
        p95_ms=percentile(latencies, 95),
        p99_ms=percentile(latencies, 99),
        max_ms=max(latencies, default=0.0),
        input_tokens=sum(row.input_tokens for row in rows),
        output_tokens=sum(row.output_tokens for row in rows),
        status_codes=status_codes,
        errors=errors,
    )
