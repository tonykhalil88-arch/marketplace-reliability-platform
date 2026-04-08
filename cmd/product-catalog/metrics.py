"""
Prometheus-compatible metrics collector.

Exposes metrics in the Prometheus text exposition format, which is
natively supported by Datadog's OpenMetrics integration. This means
the Datadog agent can scrape /metrics directly — no custom StatsD
instrumentation needed.

Key metrics for SLO tracking:
  - request_duration_seconds (histogram) → latency SLO
  - request_total (counter) → availability SLO
  - request_errors_total (counter) → error budget tracking
"""

import time
from collections import defaultdict
from typing import Callable

from fastapi import Request, Response


class MetricsCollector:
    def __init__(self, service_name: str, region: str):
        self.service_name = service_name
        self.region = region
        self.start_time = time.time()

        # Counters
        self._request_count = defaultdict(int)      # {(method, path, status): count}
        self._error_count = defaultdict(int)         # {error_type: count}

        # Histogram buckets for latency tracking (seconds)
        # Aligned with typical SLO thresholds
        self._latency_buckets = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
        self._latency_bucket_counts = defaultdict(lambda: [0] * len(self._latency_buckets))
        self._latency_sum = defaultdict(float)
        self._latency_count = defaultdict(int)

        # Gauge
        self._active_requests = 0

    def record_request(self, method: str, path: str, status_code: int, duration: float):
        """Record a completed request with its latency."""
        key = (method, self._normalize_path(path), str(status_code))
        self._request_count[key] += 1

        path_key = (method, self._normalize_path(path))
        self._latency_sum[path_key] += duration
        self._latency_count[path_key] += 1

        for i, bucket in enumerate(self._latency_buckets):
            if duration <= bucket:
                self._latency_bucket_counts[path_key][i] += 1

    def record_error(self, error_type: str):
        """Record an application-level error."""
        self._error_count[error_type] += 1

    def _normalize_path(self, path: str) -> str:
        """Normalize paths to avoid high-cardinality labels."""
        parts = path.strip("/").split("/")
        normalized = []
        for i, part in enumerate(parts):
            if i > 0 and parts[i - 1] == "products" and part.startswith("prod-"):
                normalized.append(":id")
            else:
                normalized.append(part)
        return "/" + "/".join(normalized) if normalized else "/"

    def to_prometheus_format(self) -> str:
        """Serialize all metrics to Prometheus text exposition format."""
        lines = []
        labels_base = f'service="{self.service_name}",region="{self.region}"'

        # ── Request counter ──
        lines.append("# HELP http_requests_total Total HTTP requests")
        lines.append("# TYPE http_requests_total counter")
        for (method, path, status), count in self._request_count.items():
            lines.append(
                f'http_requests_total{{{labels_base},method="{method}",path="{path}",status="{status}"}} {count}'
            )

        # ── Request duration histogram ──
        lines.append("# HELP http_request_duration_seconds Request latency histogram")
        lines.append("# TYPE http_request_duration_seconds histogram")
        for (method, path), bucket_counts in self._latency_bucket_counts.items():
            cumulative = 0
            for i, bucket in enumerate(self._latency_buckets):
                cumulative += bucket_counts[i]
                lines.append(
                    f'http_request_duration_seconds_bucket{{{labels_base},method="{method}",path="{path}",le="{bucket}"}} {cumulative}'
                )
            total = self._latency_count[(method, path)]
            lines.append(
                f'http_request_duration_seconds_bucket{{{labels_base},method="{method}",path="{path}",le="+Inf"}} {total}'
            )
            lines.append(
                f'http_request_duration_seconds_sum{{{labels_base},method="{method}",path="{path}"}} {self._latency_sum[(method, path)]:.6f}'
            )
            lines.append(
                f'http_request_duration_seconds_count{{{labels_base},method="{method}",path="{path}"}} {total}'
            )

        # ── Application errors ──
        lines.append("# HELP app_errors_total Application errors by type")
        lines.append("# TYPE app_errors_total counter")
        for error_type, count in self._error_count.items():
            lines.append(
                f'app_errors_total{{{labels_base},error_type="{error_type}"}} {count}'
            )

        # ── Active requests gauge ──
        lines.append("# HELP http_active_requests Currently active requests")
        lines.append("# TYPE http_active_requests gauge")
        lines.append(f"http_active_requests{{{labels_base}}} {self._active_requests}")

        # ── Uptime ──
        lines.append("# HELP service_uptime_seconds Service uptime")
        lines.append("# TYPE service_uptime_seconds gauge")
        lines.append(
            f"service_uptime_seconds{{{labels_base}}} {time.time() - self.start_time:.2f}"
        )

        return "\n".join(lines) + "\n"


def metrics_middleware(collector: MetricsCollector):
    """FastAPI middleware that records request metrics."""

    async def middleware(request: Request, call_next) -> Response:
        collector._active_requests += 1
        start = time.perf_counter()

        try:
            response = await call_next(request)
            duration = time.perf_counter() - start

            collector.record_request(
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
                duration=duration,
            )

            # Add server timing header (useful for debugging in browser)
            response.headers["Server-Timing"] = f"total;dur={duration * 1000:.1f}"
            return response

        except Exception as e:
            duration = time.perf_counter() - start
            collector.record_request(
                method=request.method,
                path=request.url.path,
                status_code=500,
                duration=duration,
            )
            collector.record_error("unhandled_exception")
            raise
        finally:
            collector._active_requests -= 1

    return middleware
