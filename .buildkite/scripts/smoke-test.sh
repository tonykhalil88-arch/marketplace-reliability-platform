#!/usr/bin/env bash
# ─── Smoke Test Script ──────────────────────────────────────────────────────
# Validates a deployed service is healthy and responding correctly.
# Run after each deploy to catch configuration or connectivity issues.

set -euo pipefail

TARGET_URL="${TARGET_URL:?TARGET_URL is required}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
MAX_RETRIES=5
RETRY_DELAY=10

echo "--- :stethoscope: Running smoke tests against ${TARGET_URL}"

# Helper: retry a command with backoff
retry() {
  local n=0
  until [ $n -ge $MAX_RETRIES ]; do
    "$@" && return 0
    n=$((n + 1))
    echo "  Attempt ${n}/${MAX_RETRIES} failed, retrying in ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
  done
  return 1
}

FAILURES=0

# ── Test 1: Health endpoint ──
echo "--- Test 1: Health endpoint"
HEALTH=$(retry curl -sf --max-time 10 "${TARGET_URL}/health")
STATUS=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [ "$STATUS" = "healthy" ] || [ "$STATUS" = "degraded" ]; then
  echo "  :white_check_mark: Health check passed (status: ${STATUS})"
else
  echo "  :x: Health check failed (status: ${STATUS})"
  FAILURES=$((FAILURES + 1))
fi

# ── Test 2: Product listing ──
echo "--- Test 2: Product listing endpoint"
PRODUCTS=$(retry curl -sf --max-time 10 "${TARGET_URL}/api/products")
COUNT=$(echo "$PRODUCTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
if [ "$COUNT" -gt 0 ]; then
  echo "  :white_check_mark: Product listing returned ${COUNT} products"
else
  echo "  :x: Product listing returned 0 products"
  FAILURES=$((FAILURES + 1))
fi

# ── Test 3: Single product detail ──
echo "--- Test 3: Product detail endpoint"
PRODUCT=$(retry curl -sf --max-time 10 "${TARGET_URL}/api/products/prod-001")
TITLE=$(echo "$PRODUCT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('title',''))")
if [ -n "$TITLE" ]; then
  echo "  :white_check_mark: Product detail returned: ${TITLE}"
else
  echo "  :x: Product detail returned empty or invalid response"
  FAILURES=$((FAILURES + 1))
fi

# ── Test 4: Metrics endpoint ──
echo "--- Test 4: Metrics endpoint (Prometheus format)"
METRICS=$(retry curl -sf --max-time 10 "${TARGET_URL}/metrics")
if echo "$METRICS" | grep -q "http_requests_total"; then
  echo "  :white_check_mark: Metrics endpoint returning Prometheus format"
else
  echo "  :x: Metrics endpoint not returning expected format"
  FAILURES=$((FAILURES + 1))
fi

# ── Test 5: Response headers ──
echo "--- Test 5: Response headers"
HEADERS=$(retry curl -sf --max-time 10 -I "${TARGET_URL}/api/products")
if echo "$HEADERS" | grep -qi "X-Correlation-ID"; then
  echo "  :white_check_mark: Correlation ID header present"
else
  echo "  :x: Missing X-Correlation-ID header"
  FAILURES=$((FAILURES + 1))
fi

if echo "$HEADERS" | grep -qi "Server-Timing"; then
  echo "  :white_check_mark: Server-Timing header present"
else
  echo "  :x: Missing Server-Timing header"
  FAILURES=$((FAILURES + 1))
fi

# ── Test 6: Latency check ──
echo "--- Test 6: Response time check"
RESPONSE_TIME=$(curl -sf --max-time 10 -o /dev/null -w "%{time_total}" "${TARGET_URL}/api/products")
RESPONSE_MS=$(python3 -c "print(int(float('${RESPONSE_TIME}') * 1000))")
if [ "$RESPONSE_MS" -lt 1000 ]; then
  echo "  :white_check_mark: Response time: ${RESPONSE_MS}ms (< 1000ms)"
else
  echo "  :warning: Response time: ${RESPONSE_MS}ms (slow but not failing)"
fi

# ── Results ──
echo ""
echo "--- :clipboard: Smoke Test Results"
if [ $FAILURES -eq 0 ]; then
  echo ":white_check_mark: All smoke tests passed"
  exit 0
else
  echo ":x: ${FAILURES} smoke test(s) failed"
  exit 1
fi
