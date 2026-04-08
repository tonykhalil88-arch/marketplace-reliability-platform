# ─── Datadog Monitors & SLOs as Code ─────────────────────────────────────────
# Defines SLOs, burn-rate alerts, and operational monitors as Terraform
# resources. This means observability is version-controlled, peer-reviewed,
# and deployed through the same CI/CD pipeline as the infrastructure.
#
# SLO philosophy for a marketplace:
#   - Availability SLO: "Can users browse and view products?"
#   - Latency SLO: "Are product pages fast enough to drive conversions?"
#   - Error budget policy drives deploy/freeze decisions

terraform {
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.40"
    }
  }
}

# ─── SLO: Product Catalog Availability ──────────────────────────────────────
# Target: 99.9% of requests return non-5xx responses over 30 days.
# Error budget: 43.2 minutes of downtime per month.
#
# Why 99.9% (not 99.99%): Redbubble/TeePublic are marketplaces, not
# financial systems. 99.9% balances reliability with feature velocity.

resource "datadog_service_level_objective" "availability" {
  name        = "${var.service_name} - Availability"
  type        = "metric"
  description = "Percentage of successful (non-5xx) requests to the product catalog. Directly impacts artist storefront visibility and buyer experience."

  query {
    numerator   = "sum:product_catalog.http_requests_total{service:${var.service_name},!status:5xx,environment:${var.environment}}.as_count()"
    denominator = "sum:product_catalog.http_requests_total{service:${var.service_name},environment:${var.environment}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  thresholds {
    timeframe = "7d"
    target    = 99.9
    warning   = 99.95
  }

  tags = concat(var.tags, [
    "slo:availability",
    "team:platform",
    "marketplace:${var.marketplace}",
  ])
}

# ─── SLO: Product Page Latency ──────────────────────────────────────────────
# Target: 99% of product page requests complete within 500ms.
#
# Why 500ms: Product pages are image-heavy and visually driven.
# Studies show each 100ms of latency reduces conversion by ~1%.
# 500ms at p99 keeps the experience snappy for >99% of page loads.

resource "datadog_service_level_objective" "latency" {
  name        = "${var.service_name} - Latency (p99 < ${var.latency_target_ms}ms)"
  type        = "metric"
  description = "P99 request latency for product catalog. Slow product pages directly reduce artist sales conversion rates."

  query {
    numerator   = "sum:product_catalog.http_request_duration_seconds.count{service:${var.service_name},environment:${var.environment},le:${var.latency_target_seconds}}.as_count()"
    denominator = "sum:product_catalog.http_request_duration_seconds.count{service:${var.service_name},environment:${var.environment}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.0
    warning   = 99.5
  }

  thresholds {
    timeframe = "7d"
    target    = 99.0
    warning   = 99.5
  }

  tags = concat(var.tags, [
    "slo:latency",
    "team:platform",
    "marketplace:${var.marketplace}",
  ])
}

# ─── Burn Rate Alerts ────────────────────────────────────────────────────────
# Multi-window burn rate alerting (Google SRE approach).
# Instead of alerting on raw error rates, we alert when the error budget
# is being consumed too fast — this avoids noisy alerts from brief spikes
# while catching sustained degradation early.

# Page-level alert: 1-hour window, 14.4x burn rate
# At this rate, the entire 30-day error budget would be exhausted in 2 hours.
resource "datadog_monitor" "availability_burn_rate_page" {
  name    = "[P1] ${var.service_name} - Error Budget Burn Rate Critical (${var.environment})"
  type    = "query alert"
  message = <<-EOT
    ## Error Budget Burning Too Fast 🔥

    The product catalog error budget is being consumed at **{{value}}x** the sustainable rate.
    At this pace, the 30-day error budget will be exhausted in ~2 hours.

    **Impact**: Product pages may be returning errors, preventing buyers from
    viewing artist designs on ${var.marketplace}.

    **Immediate Actions**:
    1. Check recent deployments: `buildkite builds list --pipeline product-catalog`
    2. Check downstream dependencies (artist-service circuit breaker state)
    3. Check Kubernetes pod health: `kubectl get pods -l app=product-catalog`
    4. Review error logs in Datadog Log Explorer

    **Escalation**: If not mitigated within 15 minutes, page the on-call SRE.

    @slack-${var.slack_channel} @pagerduty-${var.pagerduty_service}
  EOT

  query = <<-EOQ
    burn_rate("${datadog_service_level_objective.availability.id}").rollup("sum", 3600).last("5m") > ${var.burn_rate_critical}
  EOQ

  monitor_thresholds {
    critical = var.burn_rate_critical
  }

  notify_no_data    = false
  renotify_interval = 30
  timeout_h         = 1

  tags = concat(var.tags, [
    "severity:p1",
    "slo:availability",
    "team:platform",
    "alert-type:burn-rate",
  ])
}

# Ticket-level alert: 6-hour window, 6x burn rate
# At this rate, the error budget would be exhausted in ~5 days.
resource "datadog_monitor" "availability_burn_rate_ticket" {
  name    = "[P3] ${var.service_name} - Error Budget Burn Rate Warning (${var.environment})"
  type    = "query alert"
  message = <<-EOT
    ## Error Budget Burn Rate Elevated ⚠️

    The product catalog error budget burn rate is elevated at **{{value}}x** sustainable.
    At this pace, the error budget will be exhausted in ~5 days.

    This is not an immediate emergency but should be investigated during
    business hours. Check for:
    - Gradual degradation in downstream services
    - Increased error rates from a specific region (US vs AU)
    - Recent config changes that may have introduced issues

    @slack-${var.slack_channel}
  EOT

  query = <<-EOQ
    burn_rate("${datadog_service_level_objective.availability.id}").rollup("sum", 21600).last("30m") > ${var.burn_rate_warning}
  EOQ

  monitor_thresholds {
    critical = var.burn_rate_warning
  }

  notify_no_data    = false
  renotify_interval = 120

  tags = concat(var.tags, [
    "severity:p3",
    "slo:availability",
    "team:platform",
    "alert-type:burn-rate",
  ])
}

# ─── Latency Degradation Alert ──────────────────────────────────────────────

resource "datadog_monitor" "latency_p99" {
  name    = "[P2] ${var.service_name} - P99 Latency Exceeds SLO Target (${var.environment})"
  type    = "query alert"
  message = <<-EOT
    ## Product Catalog Latency Degraded

    P99 latency has exceeded **${var.latency_target_ms}ms** for 5+ minutes.
    Current value: **{{value}}ms**

    **Business Impact**: Slow product pages reduce conversion rates.
    Each 100ms of added latency costs approximately 1% of sales.

    **Investigation**:
    1. Check if a specific region is affected (compare US vs AU metrics)
    2. Review HPA status — are pods scaling up in response?
    3. Check circuit breaker state for artist-service dependency
    4. Look for database query slowdowns or cache misses

    @slack-${var.slack_channel}
  EOT

  query = "percentile(last_5m):p99:product_catalog.http_request_duration_seconds{service:${var.service_name},environment:${var.environment}} > ${var.latency_target_seconds}"

  monitor_thresholds {
    critical = var.latency_target_seconds
    warning  = var.latency_target_seconds * 0.8
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = concat(var.tags, [
    "severity:p2",
    "slo:latency",
    "team:platform",
  ])
}

# ─── Circuit Breaker Alert ──────────────────────────────────────────────────
# Fires when the circuit breaker opens, indicating a downstream dependency
# is unhealthy. The service will degrade gracefully (serve products without
# artist enrichment) but this should be investigated.

resource "datadog_monitor" "circuit_breaker_open" {
  name    = "[P2] ${var.service_name} - Circuit Breaker Open (${var.environment})"
  type    = "log alert"
  message = <<-EOT
    ## Circuit Breaker Opened for Downstream Dependency

    The circuit breaker for a downstream service has transitioned to OPEN state.
    The product catalog is serving **degraded responses** (products without artist data).

    This is by design — the circuit breaker prevents cascading failures —
    but the root cause should be investigated.

    **Check**:
    1. Is the artist-service healthy? `kubectl get pods -l app=artist-service`
    2. Network connectivity between services
    3. Recent deployments to dependent services

    @slack-${var.slack_channel}
  EOT

  query = "logs(\"service:${var.service_name} circuit_breaker new_state:open environment:${var.environment}\").index(\"*\").rollup(\"count\").last(\"5m\") > 0"

  monitor_thresholds {
    critical = 0
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = concat(var.tags, [
    "severity:p2",
    "team:platform",
    "alert-type:circuit-breaker",
  ])
}

# ─── Deployment Tracking Monitor ────────────────────────────────────────────
# Composite monitor: checks if error rate spikes within 10 minutes of a deploy.
# Helps correlate deployments with incidents for faster MTTR.

resource "datadog_monitor" "post_deploy_error_spike" {
  name    = "[P2] ${var.service_name} - Post-Deploy Error Spike (${var.environment})"
  type    = "query alert"
  message = <<-EOT
    ## Error Rate Spike Detected After Deployment

    Error rate increased significantly within 10 minutes of a deployment.
    This may indicate a bad release.

    **Recommended Action**: Consider rolling back the latest deployment.
    ```
    helm rollback product-catalog --namespace production
    ```

    Or via Buildkite: trigger a redeploy of the previous known-good commit.

    @slack-${var.slack_channel} @pagerduty-${var.pagerduty_service}
  EOT

  query = "avg(last_10m):anomalies(sum:product_catalog.http_requests_total{service:${var.service_name},status:5xx,environment:${var.environment}}.as_count(), 'agile', 3, direction='above') >= 0.8"

  monitor_thresholds {
    critical = 0.8
  }

  notify_no_data    = false
  renotify_interval = 0 # Don't re-notify — one alert per incident

  tags = concat(var.tags, [
    "severity:p2",
    "team:platform",
    "alert-type:deployment",
  ])
}

# ─── Error Budget Remaining Dashboard Widget Data ────────────────────────────
# (Outputs the SLO IDs so they can be embedded in Datadog dashboards)
