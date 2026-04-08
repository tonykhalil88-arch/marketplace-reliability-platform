# Marketplace Reliability Platform

A reference implementation for deploying and operating a marketplace microservice
with SLO-driven reliability. Built to demonstrate production-grade DevOps
practices for global e-commerce platforms running on Kubernetes, ECS, and AWS.

## What This Project Demonstrates

- **Multi-region Kubernetes deployments** with Helm, HPA, PDB, and pod anti-affinity
- **AWS ECS Fargate** service alongside Kubernetes (dual compute support)
- **SLOs as code** — Datadog SLOs, burn-rate alerts, and monitors defined in Terraform
- **Dual CI/CD** — Buildkite for deploys (canary + rolling), GitHub Actions for PR validation
- **Cloudflare** geo-routing, WAF, and edge caching for global traffic management
- **Circuit breaker** pattern for graceful degradation when dependencies fail
- **Cross-timezone operations** — deploy windows and alerting tuned for Melbourne + New York

## Repository Structure

```
marketplace-reliability-platform/
├── cmd/product-catalog/           # Python/FastAPI microservice
│   ├── main.py                    #   API endpoints + structured logging
│   ├── circuit_breaker.py         #   State-machine circuit breaker
│   ├── metrics.py                 #   Prometheus-format metrics collector
│   ├── models.py                  #   Pydantic data models
│   └── tests/                     #   20 unit tests (API + circuit breaker)
│
├── helm-chart/                    # Kubernetes deployment
│   ├── templates/                 #   Deployment, Service, HPA, PDB, Ingress,
│   │                              #   ServiceMonitor, ConfigMap, ServiceAccount
│   ├── values.yaml                #   Base configuration
│   ├── values-staging.yaml        #   Staging overrides
│   ├── values-production.yaml     #   Production overrides
│   ├── values-us.yaml             #   US region (us-east-1) tuning
│   └── values-au.yaml             #   AU region (ap-southeast-2) tuning
│
├── terraform/
│   ├── modules/
│   │   ├── ecs-service/           #   ECS Fargate with autoscaling + ALB
│   │   ├── cloudflare-dns/        #   Geo-routing, WAF, health checks, caching
│   │   └── datadog-monitors/      #   SLOs, burn-rate alerts, circuit breaker alerts
│   └── environments/
│       ├── staging/               #   Single-region, relaxed thresholds
│       └── production/            #   Multi-region (US+AU), strict SLOs
│
├── .buildkite/
│   ├── pipeline.yml               # Deploy pipeline: test → build → staging →
│   │                              #   canary → production (US then AU)
│   └── scripts/                   # deploy.sh, canary-analysis.sh, smoke-test.sh
│
├── .github/workflows/
│   ├── pr-checks.yml              # PR validation (tests, helm lint, tf validate,
│   │                              #   security scan, docker build)
│   ├── dependency-review.yml      # Supply chain security on dependency changes
│   └── scheduled-slo-report.yml   # Weekly SLO report (Monday 9am AEST)
│
├── slo/
│   ├── product-catalog-slos.md    # SLO definitions with business rationale
│   └── error-budget-policy.md     # Error budget tiers and response policy
│
├── docs/
│   ├── architecture.md            # System diagrams (ASCII)
│   ├── runbook.md                 # Incident response for 4 alert scenarios
│   └── onboarding.md              # Self-service guide for product teams
│
├── Dockerfile                     # Multi-stage build, non-root, health check
├── Makefile                       # Dev commands: run, test, docker, helm, tf
└── requirements.txt               # Python dependencies
```

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Run the service locally
cd cmd/product-catalog && python main.py

# Run tests (20 tests)
cd cmd/product-catalog && python -m pytest tests/ -v

# Lint Helm chart
helm lint ./helm-chart -f helm-chart/values-production.yaml -f helm-chart/values-us.yaml

# Validate Terraform
cd terraform/environments/staging && terraform init -backend=false && terraform validate
```

## Endpoints

| Endpoint              | Description                                    |
|-----------------------|------------------------------------------------|
| `GET /api/products`   | List products (filterable by marketplace/category) |
| `GET /api/products/:id` | Product detail with artist enrichment (circuit breaker protected) |
| `GET /health`         | Health check with dependency status             |
| `GET /metrics`        | Prometheus-format metrics for Datadog scraping  |

## SLO Summary

| SLO | Target | Measurement |
|-----|--------|-------------|
| Availability | 99.9% (30d) | Non-5xx / total responses |
| Latency | p99 < 500ms (US) / 700ms (AU) | Request duration histogram |
| Deploy Success | 99% without rollback | Buildkite deploy step success |
| Graceful Degradation | Products available when artist-service is down | Circuit breaker + response status |

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Application | Python 3.13, FastAPI |
| Container | Docker (multi-stage) |
| Orchestration | Kubernetes (Helm) + AWS ECS Fargate |
| Infrastructure | Terraform (AWS, Cloudflare, Datadog providers) |
| CI/CD | Buildkite (deploys) + GitHub Actions (PR validation) |
| Monitoring | Datadog (metrics, SLOs, logs, alerts) |
| Edge/CDN | Cloudflare (geo-routing, WAF, caching) |
| Security | Trivy, Checkov, pip-audit, non-root containers |
