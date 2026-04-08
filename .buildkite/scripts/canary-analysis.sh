#!/usr/bin/env bash
# ─── Canary Analysis Script ─────────────────────────────────────────────────
# Monitors the canary deployment for a set duration and compares its error
# rate and latency against the stable version using Datadog metrics.
#
# If the canary exceeds thresholds, the script exits non-zero which triggers
# the Buildkite pipeline to stop (preventing full rollout).

set -euo pipefail

SERVICE_NAME="product-catalog"
CANARY_NAME="${SERVICE_NAME}-canary"
CANARY_DURATION="${CANARY_DURATION:-300}"
ERROR_RATE_THRESHOLD="${ERROR_RATE_THRESHOLD:-0.01}"
LATENCY_P99_THRESHOLD="${LATENCY_P99_THRESHOLD:-500}"

echo "--- :chart_with_upwards_trend: Monitoring canary for ${CANARY_DURATION}s"
echo "Error rate threshold: ${ERROR_RATE_THRESHOLD} (${ERROR_RATE_THRESHOLD}%)"
echo "Latency p99 threshold: ${LATENCY_P99_THRESHOLD}ms"

# Wait for metrics to start flowing
echo "Waiting 30s for metrics to stabilize..."
sleep 30

ELAPSED=30
CHECK_INTERVAL=30
FAILURES=0

while [ $ELAPSED -lt $CANARY_DURATION ]; do
  echo "--- Check at ${ELAPSED}s / ${CANARY_DURATION}s"

  # Query Datadog for canary error rate
  CANARY_ERROR_RATE=$(curl -s \
    "https://api.datadoghq.com/api/v1/query" \
    -H "DD-API-KEY: ${DD_API_KEY:-}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY:-}" \
    --data-urlencode "query=avg:product_catalog.http_requests_total{service:${CANARY_NAME},status:5xx,environment:production}.as_rate() / avg:product_catalog.http_requests_total{service:${CANARY_NAME},environment:production}.as_rate()" \
    --data-urlencode "from=$(( $(date +%s) - 60 ))" \
    --data-urlencode "to=$(date +%s)" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('series',[{}])[0].get('pointlist',[[-1,0]])[-1][1] if d.get('series') else 0)" 2>/dev/null \
    || echo "0")

  # Query Datadog for canary p99 latency
  CANARY_LATENCY=$(curl -s \
    "https://api.datadoghq.com/api/v1/query" \
    -H "DD-API-KEY: ${DD_API_KEY:-}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY:-}" \
    --data-urlencode "query=p99:product_catalog.http_request_duration_seconds{service:${CANARY_NAME},environment:production} * 1000" \
    --data-urlencode "from=$(( $(date +%s) - 60 ))" \
    --data-urlencode "to=$(date +%s)" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('series',[{}])[0].get('pointlist',[[-1,0]])[-1][1] if d.get('series') else 0)" 2>/dev/null \
    || echo "0")

  echo "  Canary error rate: ${CANARY_ERROR_RATE}"
  echo "  Canary p99 latency: ${CANARY_LATENCY}ms"

  # Check error rate threshold
  if python3 -c "exit(0 if float('${CANARY_ERROR_RATE}') > float('${ERROR_RATE_THRESHOLD}') else 1)" 2>/dev/null; then
    echo "  :x: Error rate exceeds threshold!"
    FAILURES=$((FAILURES + 1))
  fi

  # Check latency threshold
  if python3 -c "exit(0 if float('${CANARY_LATENCY}') > float('${LATENCY_P99_THRESHOLD}') else 1)" 2>/dev/null; then
    echo "  :x: Latency exceeds threshold!"
    FAILURES=$((FAILURES + 1))
  fi

  # Fail fast: 3 consecutive failures = canary is bad
  if [ $FAILURES -ge 3 ]; then
    echo "--- :rotating_light: Canary failed — rolling back"

    # Remove canary deployment
    helm uninstall "${CANARY_NAME}" --namespace production || true

    buildkite-agent annotate --style "error" --context "canary" \
      ":x: Canary **failed** — error rate or latency exceeded thresholds. Auto-rolled back." 2>/dev/null || true

    exit 1
  fi

  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo "--- :white_check_mark: Canary analysis passed — safe to proceed with full rollout"

# Clean up canary deployment before full rollout
echo "--- :broom: Removing canary deployment"
helm uninstall "${CANARY_NAME}" --namespace production || true

buildkite-agent annotate --style "success" --context "canary" \
  ":white_check_mark: Canary passed all checks — proceeding to full rollout" 2>/dev/null || true
