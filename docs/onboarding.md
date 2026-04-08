# Self-Service Deployment Guide

> For product and feature teams deploying services on the marketplace platform.
> Maintained by: Platform Engineering

---

## Overview

This guide shows how to deploy a new microservice (or adopt the patterns used
by `product-catalog`) on our shared infrastructure. The platform team provides
the building blocks — you wire them together for your service.

**What the platform provides:**
- Kubernetes clusters (US + AU regions)
- CI/CD pipeline templates (Buildkite + GitHub Actions)
- Observability (Datadog integration, SLO templates)
- Cloudflare routing and edge caching
- Helm chart templates with production-ready defaults

**What your team owns:**
- Your service code and Dockerfile
- Your Helm values (resource sizing, replica counts)
- Your SLO targets (we provide templates, you set thresholds)
- Your on-call rotation for service-specific alerts

---

## Step 1: Start from the Template

Copy the product-catalog structure as your starting point:

```bash
cp -r helm-chart/ ../your-service/helm-chart/
cp .buildkite/pipeline.yml ../your-service/.buildkite/pipeline.yml
cp -r .github/workflows/ ../your-service/.github/workflows/
cp -r terraform/modules/datadog-monitors/ ../your-service/terraform/modules/datadog-monitors/
```

## Step 2: Configure Your Helm Chart

Edit `helm-chart/values.yaml` for your service:

```yaml
# Minimum changes needed:
image:
  repository: 123456789.dkr.ecr.us-east-1.amazonaws.com/YOUR-SERVICE

config:
  region: "us-east-1"         # Deployment region
  environment: "production"

resources:
  requests:
    cpu: 100m      # Start small, adjust based on load testing
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2    # Minimum for HA (anti-affinity spreads across nodes)
  maxReplicas: 10   # Adjust based on expected traffic
```

### Key Decisions

| Decision | Recommendation | Why |
|----------|---------------|-----|
| Min replicas | 2+ in production | Pod anti-affinity needs 2+ for node spread |
| HPA metric | CPU + custom latency | CPU catches compute bottlenecks; latency catches I/O |
| PDB | 50% minAvailable | Survives single-node failure during upgrades |
| Readiness probe | Aggressive (5s interval) | Pull unhealthy pods from LB quickly |
| Liveness probe | Conservative (15s interval) | Avoid killing pods during transient issues |

## Step 3: Define Your SLOs

Use the Datadog Terraform module. Minimum SLOs for any production service:

```hcl
module "datadog_monitors" {
  source = "../../modules/datadog-monitors"

  service_name   = "your-service"
  environment    = "production"
  marketplace    = "redbubble"  # or "teepublic"
  slack_channel  = "your-team-alerts"

  # Set these based on your service's requirements:
  latency_target_ms      = 500   # What p99 should your users experience?
  latency_target_seconds = 0.5
  pagerduty_service      = "your-team-oncall"
}
```

### Choosing SLO Targets

| Service Type | Suggested Availability | Suggested Latency (p99) |
|-------------|----------------------|------------------------|
| User-facing API | 99.9% | 500ms |
| Internal API | 99.5% | 1000ms |
| Batch/async | 99.0% | N/A |
| Payment/checkout | 99.95% | 300ms |

## Step 4: Set Up Your Pipeline

### Buildkite (deploys)

Edit `.buildkite/pipeline.yml`:
- Update service name and ECR repository
- Adjust agent queues if your team has dedicated build agents
- Configure the block step with your team's deploy checklist

### GitHub Actions (PR checks)

The template workflows should work out of the box. Customize:
- `pr-checks.yml`: Add your language-specific test commands
- `dependency-review.yml`: Already triggers on `requirements.txt` changes

## Step 5: Multi-Region Checklist

Before deploying to both US and AU:

- [ ] Create region-specific values files (`values-us.yaml`, `values-au.yaml`)
- [ ] Adjust circuit breaker timeouts for AU (add ~150ms for cross-region)
- [ ] Set up Cloudflare geo-routing (ask platform team)
- [ ] Configure region-specific HPA thresholds
- [ ] Test failover: what happens when one region goes down?
- [ ] Ensure deploy pipeline deploys US first, then AU (sequential)

## Step 6: Go Live Checklist

Before your first production deploy:

- [ ] Helm chart lints with all values file combinations
- [ ] Terraform validates for staging and production
- [ ] Datadog SLOs created and visible in the SLO dashboard
- [ ] Alerts routing to your team's Slack channel
- [ ] PagerDuty service configured for P1 alerts
- [ ] Runbook written (use `docs/runbook.md` as template)
- [ ] Staging deploy successful with passing smoke tests
- [ ] On-call rotation established for your team
- [ ] Platform team review of Helm chart and Terraform (request in #platform-support)

---

## Getting Help

| Need | Where |
|------|-------|
| Pipeline issues | #platform-support (Slack) |
| Infrastructure requests | JIRA project: PLATFORM |
| Urgent production issues | PagerDuty: marketplace-oncall |
| Architecture review | Book with Platform Engineering (Calendly link) |
| SLO guidance | See `slo/` directory or ask in #platform-support |
