# Product Catalog SLOs

> Service: `product-catalog`
> Owner: Platform Engineering
> Last reviewed: 2026-04-08
> Review cadence: Quarterly

## Why These SLOs Matter

The product catalog is the primary browsing experience for both Redbubble and
TeePublic. When product pages are slow or unavailable, artists lose sales and
buyers leave. These SLOs are designed to protect the revenue-generating path:
**buyer browses products -> views product detail -> adds to cart**.

---

## SLO 1: Availability

| Field               | Value                                               |
|---------------------|-----------------------------------------------------|
| **Target**          | 99.9% over 30-day rolling window                    |
| **SLI Definition**  | Non-5xx responses / total responses                 |
| **Measurement**     | Datadog metric: `http_requests_total` by status     |
| **Error Budget**    | 43.2 minutes of effective downtime per month         |
| **Scope**           | All `/api/products*` endpoints, both marketplaces   |
| **Exclusions**      | Planned maintenance windows (announced 48h ahead)   |

### Why 99.9%?

- Product browsing is critical but not life-safety. 99.99% would be too
  restrictive for a marketplace shipping multiple times per day.
- 43 minutes/month of error budget gives the team room to deploy confidently
  while still catching sustained degradation.
- This target aligns with typical e-commerce industry standards for catalog
  services (order/payment flows may warrant 99.95%+).

### Burn Rate Alert Thresholds

| Severity | Window  | Burn Rate | Time to Budget Exhaustion | Action           |
|----------|---------|-----------|---------------------------|------------------|
| P1 Page  | 1 hour  | 14.4x     | ~2 hours                  | PagerDuty + Slack |
| P3 Ticket| 6 hours | 6x        | ~5 days                   | Slack only        |

The multi-window approach (from Google's SRE workbook) avoids alerting on
brief spikes while catching sustained degradation before the budget runs out.

---

## SLO 2: Latency

| Field               | Value                                               |
|---------------------|-----------------------------------------------------|
| **Target**          | 99% of requests complete within 500ms (p99)         |
| **SLI Definition**  | Requests with duration <= 500ms / total requests    |
| **Measurement**     | Datadog histogram: `http_request_duration_seconds`  |
| **Scope**           | GET `/api/products` and `/api/products/:id`         |
| **Region Variance** | US: 500ms target / AU: 700ms target (cross-region)  |

### Why 500ms at p99?

- Marketplace product pages are visual-first — buyers scroll through designs.
  Research shows each 100ms of added latency reduces conversion by ~1%.
- p99 (not p50 or p95) ensures the tail latency doesn't create a miserable
  experience for a significant minority of users.
- The AU region has a relaxed 700ms target because cross-region calls to
  US-hosted dependencies add ~150ms of unavoidable network latency.

### Alert Threshold

| Severity | Condition                    | Action      |
|----------|------------------------------|-------------|
| P2       | p99 > 500ms for 5+ minutes   | Slack alert |

---

## SLO 3: Deployment Success Rate

| Field               | Value                                               |
|---------------------|-----------------------------------------------------|
| **Target**          | 99% of deployments succeed without rollback          |
| **SLI Definition**  | Successful Buildkite deploy steps / total deploys   |
| **Measurement**     | Buildkite API + Datadog deploy events               |
| **Rollback SLI**    | Time from failure detection to rollback < 5 min     |

### Why Track This?

Deployment reliability directly impacts feature velocity. If deploys are
unreliable, engineers slow down, batch larger changes, and increase risk.
Tracking this SLO creates accountability for pipeline health.

---

## SLO 4: Graceful Degradation

| Field               | Value                                               |
|---------------------|-----------------------------------------------------|
| **Target**          | Product pages remain available when artist-service is down |
| **SLI Definition**  | Product detail requests return 200 even when artist enrichment fails |
| **Measurement**     | Circuit breaker state logs + response status codes  |
| **Validation**      | Chaos engineering: periodic artist-service failure injection |

This SLO ensures our circuit breaker pattern works correctly. Buyers should
always be able to browse products, even if artist profiles are temporarily
unavailable.

---

## Dashboards

| Dashboard           | URL                                                  | Purpose                  |
|---------------------|------------------------------------------------------|--------------------------|
| SLO Overview        | `https://app.datadoghq.com/slo?query=service:product-catalog` | Error budget status |
| Service Dashboard   | `https://app.datadoghq.com/dashboard/product-catalog`          | Real-time metrics   |
| Deploy Tracking     | `https://app.datadoghq.com/events?query=source:buildkite`     | Deploy correlation  |
