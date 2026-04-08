# Product Catalog — Incident Runbook

> Service: `product-catalog`
> On-call: Platform Engineering rotation
> Escalation: #platform-prod-alerts (Slack) → PagerDuty marketplace-oncall

---

## Quick Reference

| Action                  | Command                                                            |
|-------------------------|--------------------------------------------------------------------|
| Check pod status        | `kubectl get pods -l app=product-catalog -n production`            |
| View recent logs        | `kubectl logs -l app=product-catalog -n production --tail=100`     |
| Check circuit breaker   | `kubectl logs -l app=product-catalog -n production \| grep circuit_breaker` |
| Rollback last deploy    | `helm rollback product-catalog --namespace production`             |
| Force restart all pods  | `kubectl rollout restart deployment/product-catalog -n production` |
| Check HPA status        | `kubectl get hpa product-catalog -n production`                    |
| Datadog SLO dashboard   | `https://app.datadoghq.com/slo?query=service:product-catalog`     |
| Buildkite deploys       | `https://buildkite.com/articore/product-catalog`                   |

---

## Scenario 1: Error Budget Burn Rate Alert (P1)

**Alert**: `[P1] product-catalog - Error Budget Burn Rate Critical`
**Meaning**: Error budget is being consumed at 14.4x sustainable rate. At this
pace, the 30-day budget will be exhausted in ~2 hours.

### Triage Steps

1. **Check if there was a recent deploy**
   ```bash
   # Check Buildkite for recent deploys
   curl -s "https://api.datadoghq.com/api/v1/events?tags=service:product-catalog,alert-type:deployment" \
     -H "DD-API-KEY: $DD_API_KEY" | python3 -m json.tool
   ```
   If deploy within last 15 minutes → likely bad release → **rollback immediately**.

2. **Check which region is affected**
   - US: `https://catalog-us.marketplace.com/health`
   - AU: `https://catalog-au.marketplace.com/health`
   - If single region → may be regional infrastructure issue.

3. **Check downstream dependencies**
   ```bash
   kubectl logs -l app=product-catalog -n production --tail=50 | grep "circuit_breaker"
   ```
   If circuit breaker OPEN → artist-service is the root cause → escalate to
   artist-service team.

4. **Check pod health**
   ```bash
   kubectl get pods -l app=product-catalog -n production -o wide
   kubectl top pods -l app=product-catalog -n production
   ```
   Look for: CrashLoopBackOff, OOMKilled, excessive CPU/memory usage.

5. **Check HPA — is it scaling?**
   ```bash
   kubectl describe hpa product-catalog -n production
   ```
   If at max replicas and still overloaded → consider temporarily increasing
   `maxReplicas` or scaling up node pool.

### Recovery Actions

| Root Cause              | Action                                              |
|-------------------------|-----------------------------------------------------|
| Bad deploy              | `helm rollback product-catalog -n production`       |
| Downstream failure      | Verify circuit breaker is protecting; escalate       |
| Traffic spike           | HPA should handle; increase max if needed            |
| Node/infra issue        | Check cluster events: `kubectl get events -n production` |
| Unknown                 | Enable debug logging: update ConfigMap LOG_LEVEL=debug |

---

## Scenario 2: Latency Degradation (P2)

**Alert**: `[P2] product-catalog - P99 Latency Exceeds SLO Target`
**Meaning**: p99 request latency has exceeded 500ms for 5+ minutes.

### Triage Steps

1. **Identify affected endpoints**
   Check Datadog APM: which endpoint has the highest latency?
   - `/api/products` (listing) → likely database or cache issue
   - `/api/products/:id` (detail) → likely artist-service enrichment

2. **Check if region-specific**
   Compare US vs AU latency in Datadog. If only AU → cross-region call
   latency may have increased (check VPC peering / transit gateway).

3. **Check artist-service circuit breaker state**
   If HALF_OPEN → the breaker is testing recovery and may be adding latency
   from retry attempts.

4. **Check pod resources**
   ```bash
   kubectl top pods -l app=product-catalog -n production
   ```
   If CPU near limits → pods are throttled → HPA should scale, or increase
   resource limits.

### Recovery Actions

| Root Cause              | Action                                              |
|-------------------------|-----------------------------------------------------|
| Artist-service slow     | Circuit breaker should protect; check threshold tuning |
| High CPU (throttling)   | Increase resource limits or HPA max replicas        |
| Network latency (AU)    | Check transit gateway / VPC peering metrics          |
| Cache miss storm        | Verify Cloudflare edge cache is working (check hit rate) |

---

## Scenario 3: Circuit Breaker Open (P2)

**Alert**: `[P2] product-catalog - Circuit Breaker Open`
**Meaning**: The circuit breaker for a downstream dependency (artist-service)
has opened. Product pages are being served without artist enrichment data.

### Impact

- **User-visible**: Product pages load but show "Artist info unavailable"
  instead of artist profile data. Core product browsing still works.
- **Business impact**: Low — buyers can still view and purchase products.
  Artist profiles are enrichment, not critical path.

### Triage Steps

1. **This is working as designed** — the circuit breaker is protecting the
   product catalog from cascading failure. Don't panic.

2. **Investigate the artist-service**
   ```bash
   kubectl get pods -l app=artist-service -n production
   kubectl logs -l app=artist-service -n production --tail=50
   ```

3. **Check when the breaker will attempt recovery**
   Recovery timeout is configured in the ConfigMap:
   - US: 30 seconds
   - AU: 45 seconds (longer due to cross-region latency)

4. **If artist-service is truly down**, the circuit breaker will keep
   retrying every recovery period. No action needed from the product-catalog
   side — focus on fixing artist-service.

---

## Scenario 4: Post-Deploy Error Spike

**Alert**: `[P2] product-catalog - Post-Deploy Error Spike`
**Meaning**: Error rate increased anomalously within 10 minutes of a deploy.

### Immediate Action

```bash
# Rollback immediately — investigate after recovery
helm rollback product-catalog --namespace production
```

### Post-Rollback Investigation

1. Check Buildkite for the failed deploy's diff
2. Review structured logs for the error:
   ```bash
   kubectl logs -l app=product-catalog -n production --previous --tail=200
   ```
3. Common causes:
   - Missing environment variable (check ConfigMap)
   - Incompatible dependency version
   - Schema change not backward-compatible
   - Incorrect image tag

### Prevention

- Always deploy to staging first (pipeline enforces this)
- Use canary deploys for production (pipeline block step)
- Ensure backward-compatible changes (especially for shared databases)

---

## Escalation Path

| Time Since Alert | Action                                              |
|------------------|-----------------------------------------------------|
| 0-5 min          | On-call acknowledges, begins triage                 |
| 5-15 min         | If not mitigated, page secondary on-call            |
| 15-30 min        | If not mitigated, escalate to engineering manager   |
| 30+ min          | Incident commander declares incident, war room      |

---

## Post-Incident

After every P1 or extended P2:

1. Create incident timeline in the incident tracker
2. Schedule blameless post-mortem within 48 hours
3. Document action items with owners and due dates
4. Update this runbook if new scenarios were encountered
5. Review whether SLO targets need adjustment
