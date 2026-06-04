"""Command-line interface for Claude API load tests."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import asdict
from typing import Any

from .config import build_config, load_config_file
from .runner import run_load_test


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Load-test the Anthropic Claude Messages API.")
    parser.add_argument("--config", help="Optional JSON config file. CLI flags override file values.")
    parser.add_argument("--api-key", help="Anthropic API key. Defaults to ANTHROPIC_API_KEY.")
    parser.add_argument("--model", help="Claude model name.")
    parser.add_argument("--prompt", help="Prompt sent in each request.")
    parser.add_argument("--base-url", help="API base URL, useful for staging or mocks.")
    parser.add_argument("--path", help="API path. Defaults to /v1/messages.")
    parser.add_argument("--anthropic-version", help="Anthropic API version header.")
    parser.add_argument("-n", "--total-requests", type=int, help="Total number of requests to send.")
    parser.add_argument("-c", "--concurrency", type=int, help="Concurrent workers.")
    parser.add_argument("--max-tokens", type=int, help="max_tokens value for each Claude request.")
    parser.add_argument("--timeout-seconds", type=float, help="Per-request timeout in seconds.")
    parser.add_argument("--request-interval-seconds", type=float, help="Sleep after each request per worker.")
    parser.add_argument("--output", help="Write detailed JSON results to this path.")
    parser.add_argument("--json", action="store_true", help="Print summary as JSON instead of a table.")
    return parser


def _clean_overrides(values: dict[str, Any]) -> dict[str, Any]:
    ignored = {"config", "output", "json"}
    return {key: value for key, value in values.items() if key not in ignored and value is not None}


def _print_table(summary: dict[str, Any]) -> None:
    rows = [
        ("total", summary["total_requests"]),
        ("success", summary["success_count"]),
        ("failure", summary["failure_count"]),
        ("rps", f"{summary['rps']:.2f}"),
        ("avg_ms", f"{summary['avg_ms']:.2f}"),
        ("p50_ms", f"{summary['p50_ms']:.2f}"),
        ("p90_ms", f"{summary['p90_ms']:.2f}"),
        ("p95_ms", f"{summary['p95_ms']:.2f}"),
        ("p99_ms", f"{summary['p99_ms']:.2f}"),
        ("max_ms", f"{summary['max_ms']:.2f}"),
        ("input_tokens", summary["input_tokens"]),
        ("output_tokens", summary["output_tokens"]),
    ]
    width = max(len(name) for name, _ in rows)
    for name, value in rows:
        print(f"{name:<{width}}  {value}")
    if summary["status_codes"]:
        print(f"{'status_codes':<{width}}  {summary['status_codes']}")
    if summary["errors"]:
        print(f"{'errors':<{width}}  {summary['errors']}")


async def _run(args: argparse.Namespace) -> int:
    file_config = load_config_file(args.config) if args.config else {}
    config = build_config({**file_config, **_clean_overrides(vars(args))})
    result = await run_load_test(config)
    summary = asdict(result.summary)

    if args.output:
        result.write_json(args.output)

    if args.json:
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        _print_table(summary)

    return 0 if result.summary.failure_count == 0 else 2


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = _parser().parse_args(argv)
    try:
        return asyncio.run(_run(args))
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
