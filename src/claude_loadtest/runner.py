"""Async load-test runner for the Claude Messages API."""

from __future__ import annotations

import asyncio
from dataclasses import asdict, dataclass
import json
import time
from pathlib import Path
from typing import Any

import httpx

from .config import LoadTestConfig
from .metrics import MetricsSummary, RequestMetric, summarize


@dataclass(slots=True)
class LoadTestResult:
    """Complete result from one load-test run."""

    summary: MetricsSummary
    requests: list[RequestMetric]
    elapsed_seconds: float

    def to_dict(self) -> dict[str, Any]:
        """Serialize the result to a JSON-friendly dictionary."""
        return {
            "elapsed_seconds": self.elapsed_seconds,
            "summary": asdict(self.summary),
            "requests": [asdict(item) for item in self.requests],
        }

    def write_json(self, path: str | Path) -> None:
        """Write the load-test result to disk as formatted JSON."""
        output_path = Path(path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(self.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")


def _payload(config: LoadTestConfig) -> dict[str, Any]:
    return {
        "model": config.model,
        "max_tokens": config.max_tokens,
        "messages": [{"role": "user", "content": config.prompt}],
    }


def _headers(config: LoadTestConfig) -> dict[str, str]:
    headers = {
        "x-api-key": config.api_key,
        "anthropic-version": config.anthropic_version,
        "content-type": "application/json",
    }
    headers.update(config.extra_headers)
    return headers


def _error_label(response: httpx.Response | None, exc: Exception | None) -> str | None:
    if exc is not None:
        return exc.__class__.__name__
    if response is None or 200 <= response.status_code < 300:
        return None
    try:
        body = response.json()
    except ValueError:
        return response.text[:120] or f"HTTP {response.status_code}"
    error = body.get("error") if isinstance(body, dict) else None
    if isinstance(error, dict) and error.get("type"):
        return str(error["type"])
    return f"HTTP {response.status_code}"


async def _send_one(client: httpx.AsyncClient, config: LoadTestConfig, index: int) -> RequestMetric:
    started = time.perf_counter()
    response: httpx.Response | None = None
    exc: Exception | None = None
    input_tokens = 0
    output_tokens = 0

    try:
        response = await client.post(config.endpoint, headers=_headers(config), json=_payload(config))
        if response.headers.get("content-type", "").startswith("application/json"):
            body = response.json()
            usage = body.get("usage", {}) if isinstance(body, dict) else {}
            if isinstance(usage, dict):
                input_tokens = int(usage.get("input_tokens") or 0)
                output_tokens = int(usage.get("output_tokens") or 0)
    except Exception as caught:  # noqa: BLE001 - benchmark must record transport errors instead of crashing
        exc = caught

    latency_ms = (time.perf_counter() - started) * 1000
    status_code = response.status_code if response is not None else None
    ok = exc is None and response is not None and 200 <= response.status_code < 300
    return RequestMetric(
        index=index,
        ok=ok,
        status_code=status_code,
        latency_ms=latency_ms,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        error=_error_label(response, exc),
    )


async def run_load_test(config: LoadTestConfig) -> LoadTestResult:
    """Run a bounded-concurrency load test against Claude's Messages API."""
    config.validate()
    queue: asyncio.Queue[int] = asyncio.Queue()
    for index in range(config.total_requests):
        queue.put_nowait(index)

    metrics: list[RequestMetric] = []
    metrics_lock = asyncio.Lock()
    timeout = httpx.Timeout(config.timeout_seconds)
    limits = httpx.Limits(max_connections=config.concurrency, max_keepalive_connections=config.concurrency)

    async def worker() -> None:
        async with httpx.AsyncClient(timeout=timeout, limits=limits) as client:
            while True:
                try:
                    index = queue.get_nowait()
                except asyncio.QueueEmpty:
                    return
                try:
                    metric = await _send_one(client, config, index)
                    async with metrics_lock:
                        metrics.append(metric)
                    if config.request_interval_seconds:
                        await asyncio.sleep(config.request_interval_seconds)
                finally:
                    queue.task_done()

    started = time.perf_counter()
    await asyncio.gather(*(worker() for _ in range(min(config.concurrency, config.total_requests))))
    elapsed_seconds = time.perf_counter() - started
    metrics.sort(key=lambda item: item.index)
    return LoadTestResult(
        summary=summarize(metrics, elapsed_seconds),
        requests=metrics,
        elapsed_seconds=elapsed_seconds,
    )
