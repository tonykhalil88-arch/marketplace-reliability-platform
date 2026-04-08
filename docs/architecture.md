# Architecture

## System Overview

```
                         ┌─────────────────────────────────────────────┐
                         │              Cloudflare Edge                │
                         │  ┌─────────┐  ┌──────┐  ┌──────────────┐  │
   Buyers ──────────────▶│  │ WAF/DDoS│  │ Cache│  │ Geo-Routing  │  │
   (Global)              │  └────┬────┘  └──┬───┘  └──────┬───────┘  │
                         └───────┼──────────┼─────────────┼───────────┘
                                 │          │             │
                    ┌────────────┴──────────┴─┐    ┌─────┴────────────────┐
                    │   US Region (us-east-1)  │    │  AU Region (ap-se-2) │
                    │                          │    │                      │
                    │  ┌────────────────────┐  │    │  ┌────────────────┐  │
                    │  │     ALB / Ingress   │  │    │  │  ALB / Ingress │  │
                    │  └─────────┬──────────┘  │    │  └───────┬────────┘  │
                    │            │              │    │          │            │
                    │  ┌─────────▼──────────┐  │    │  ┌───────▼────────┐  │
                    │  │   Kubernetes / ECS   │  │    │  │ Kubernetes/ECS│  │
                    │  │                      │  │    │  │                │  │
                    │  │  ┌──────────────┐   │  │    │  │ ┌────────────┐│  │
                    │  │  │product-catalog│   │  │    │  │ │prod-catalog││  │
                    │  │  │  (3-20 pods) │   │  │    │  │ │ (2-10 pods)││  │
                    │  │  │              │   │  │    │  │ │             ││  │
                    │  │  │  ┌────────┐  │   │  │    │  │ │ ┌────────┐ ││  │
                    │  │  │  │Circuit │  │   │  │    │  │ │ │Circuit │ ││  │
                    │  │  │  │Breaker │  │   │  │    │  │ │ │Breaker │ ││  │
                    │  │  │  └───┬────┘  │   │  │    │  │ │ └───┬────┘ ││  │
                    │  │  └──────┼───────┘   │  │    │  │ └─────┼──────┘│  │
                    │  └─────────┼───────────┘  │    │  └───────┼───────┘  │
                    │            │               │    │          │           │
                    │  ┌─────────▼──────────┐   │    │          │           │
                    │  │  artist-service     │   │    │          │           │
                    │  │  (downstream dep)   │◀──┼────┼──────────┘           │
                    │  └────────────────────┘   │    │  (cross-region call) │
                    └───────────────────────────┘    └──────────────────────┘
                                 │                              │
                    ┌────────────┴──────────────────────────────┴────────┐
                    │                    Datadog                          │
                    │  ┌──────────┐  ┌───────────┐  ┌────────────────┐  │
                    │  │ Metrics  │  │ SLOs/Burn │  │ Log Aggregation│  │
                    │  │ (OpenM.) │  │   Rates   │  │ (Structured)   │  │
                    │  └──────────┘  └───────────┘  └────────────────┘  │
                    └───────────────────────────────────────────────────┘
```

## CI/CD Flow

```
  Developer                GitHub                  Buildkite               Kubernetes
     │                        │                        │                       │
     │── push branch ────────▶│                        │                       │
     │                        │── PR Validation ──┐    │                       │
     │                        │   - Tests         │    │                       │
     │                        │   - Helm lint     │    │                       │
     │                        │   - TF validate   │    │                       │
     │                        │   - Security scan │    │                       │
     │                        │   - Docker build  │    │                       │
     │                        │◀──────────────────┘    │                       │
     │                        │                        │                       │
     │── merge to main ──────▶│── trigger ────────────▶│                       │
     │                        │                        │── Test ──────────┐    │
     │                        │                        │── Build image    │    │
     │                        │                        │── Push to ECR    │    │
     │                        │                        │◀─────────────────┘    │
     │                        │                        │                       │
     │                        │                        │── Deploy staging ────▶│
     │                        │                        │── Smoke tests ───────▶│
     │                        │                        │                       │
     │                        │                        │── [Manual Gate] ──┐   │
     │                        │                        │   Deploy checklist│   │
     │                        │                        │   Strategy select │   │
     │                        │                        │◀──────────────────┘   │
     │                        │                        │                       │
     │                        │                        │── Canary (10% US) ───▶│
     │                        │                        │── Analyze (5min) ─┐   │
     │                        │                        │   Query Datadog   │   │
     │                        │                        │◀──────────────────┘   │
     │                        │                        │                       │
     │                        │                        │── Full rollout US ───▶│
     │                        │                        │── Smoke test US ─────▶│
     │                        │                        │── Deploy AU ─────────▶│
     │                        │                        │── Smoke test AU ─────▶│
     │                        │                        │                       │
     │                        │                        │── Notify Slack        │
     │                        │                        │── Datadog deploy event│
```

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Compute | K8s + ECS (both) | Articore uses both; demonstrates fluency |
| CI for PRs | GitHub Actions | Fast feedback for developers without Buildkite access |
| CI for deploys | Buildkite | Production deploy pipeline with manual gates |
| Monitoring | Datadog (Prometheus-compatible) | Unified metrics/logs/traces with SLO support |
| Edge | Cloudflare | Geo-routing, WAF, edge caching for product data |
| IaC | Terraform + Helm | Terraform for cloud resources; Helm for K8s workloads |
| Resilience | Circuit breaker + graceful degradation | Products available even when dependencies fail |
| Deploy strategy | Canary → rolling (sequential US then AU) | Limits blast radius; AU deploys after US validation |
| SLO alerting | Multi-window burn rate | Avoids noisy alerts while catching sustained degradation |
