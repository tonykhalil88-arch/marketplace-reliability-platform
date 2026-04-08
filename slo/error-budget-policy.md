# Error Budget Policy

> Applies to: `product-catalog` service
> Stakeholders: Platform Engineering, Product Teams, Engineering Leadership
> Effective: 2026-04-08

## Purpose

This policy defines how the team responds to error budget consumption. It
creates a shared agreement between platform engineers (who maintain reliability)
and product teams (who ship features) about when to prioritize what.

Without this policy, reliability vs. velocity decisions become political.
With it, the data decides.

---

## Budget Tiers

### Green: Budget > 50% remaining

| Aspect           | Policy                                              |
|------------------|-----------------------------------------------------|
| Feature work     | Ship freely, normal velocity                        |
| Deploy frequency | No restrictions                                     |
| Review required  | Standard code review                                |
| Risk tolerance   | Higher — team can experiment and iterate quickly     |

**Mindset**: "We have room to move fast. Use it."

### Yellow: Budget 20–50% remaining

| Aspect           | Policy                                              |
|------------------|-----------------------------------------------------|
| Feature work     | Continue, but with caution                          |
| Deploy frequency | No deploys after 4pm Friday (any timezone)          |
| Review required  | Standard + deploy buddy for production              |
| Risk tolerance   | Medium — canary deploys mandatory                   |
| Additional       | Post-deploy smoke tests must pass before proceeding |

**Mindset**: "We're burning faster than sustainable. Be deliberate."

### Orange: Budget 5–20% remaining

| Aspect           | Policy                                              |
|------------------|-----------------------------------------------------|
| Feature work     | Paused for this service; reliability work only       |
| Deploy frequency | Max 1 deploy per day, AM only (overlapping hours)   |
| Review required  | SRE approval required for all changes               |
| Risk tolerance   | Low — no schema migrations, no dependency upgrades   |
| Additional       | Daily standup focused on budget recovery             |

**Mindset**: "We're close to the edge. Every change needs justification."

### Red: Budget < 5% or exhausted

| Aspect           | Policy                                              |
|------------------|-----------------------------------------------------|
| Feature work     | Frozen                                              |
| Deploy frequency | Emergency fixes only, with rollback plan            |
| Review required  | Engineering manager + SRE sign-off                  |
| Risk tolerance   | Near-zero — only deploy to fix the SLO breach       |
| Additional       | Incident review required before any non-fix deploy  |
| Escalation       | Weekly report to engineering leadership              |

**Mindset**: "Our users are feeling this. Fix it before anything else."

---

## Cross-Timezone Considerations

Articore operates across Melbourne (AEST) and New York (ET). The error budget
policy accounts for this:

- **No Friday deploys after 4pm in ANY active timezone** (Yellow tier+).
  This means no deploys after 4pm AEST on Friday until Monday 9am AEST,
  ensuring on-call engineers aren't firefighting weekend incidents.

- **"Overlapping hours" deploys** (Orange tier) = 9am–12pm AEST / 7pm–10pm ET.
  This window ensures engineers in both timezones are available if something
  goes wrong.

- **Weekly SLO review** is scheduled for Monday 9am AEST, giving the AU team
  first look and the US team time to prepare before their Monday.

---

## Budget Recovery Actions

When the budget is Orange or Red, the team should prioritize:

1. **Identify the top error contributor** — which endpoint, region, or
   dependency is consuming the most budget?
2. **Quick wins first** — can we add caching, tune timeouts, or adjust
   circuit breaker thresholds to recover?
3. **Reduce blast radius** — can we feature-flag or dark-launch risky changes?
4. **Improve observability** — do we have enough visibility to diagnose the
   next issue faster?

---

## Quarterly Review

Every quarter, the team reviews:

1. Was the SLO target appropriate? (Too tight = constant freezes. Too loose = user pain.)
2. Did the error budget policy drive the right behaviors?
3. Were there incidents that the SLO didn't catch? (Indicates missing SLIs.)
4. Should regional targets be adjusted based on traffic pattern changes?

The outcome is documented and shared with engineering leadership.
