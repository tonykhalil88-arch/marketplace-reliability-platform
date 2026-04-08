#!/usr/bin/env bash
# ─── Canary Deploy Script ───────────────────────────────────────────────────
# Deploys the new version as a canary alongside the current production version.
# Uses Kubernetes labels to split traffic via the ingress controller.
#
# Canary strategy:
#   1. Deploy new version as a separate deployment (product-catalog-canary)
#   2. Configure ingress to route CANARY_WEIGHT% of traffic to the canary
#   3. Canary analysis script monitors error rate and latency
#   4. If healthy → full rollout; if degraded → automatic rollback

set -euo pipefail

SERVICE_NAME="product-catalog"
CANARY_NAME="${SERVICE_NAME}-canary"
CHART_PATH="./helm-chart"
CANARY_WEIGHT="${CANARY_WEIGHT:-10}"

echo "--- :canary: Deploying canary (${CANARY_WEIGHT}% traffic)"
echo "Image tag: ${IMAGE_TAG}"
echo "Region: ${DEPLOY_REGION}"

# Deploy the canary as a separate release with reduced replicas
helm upgrade --install "${CANARY_NAME}" "${CHART_PATH}" \
  -f "${CHART_PATH}/values-production.yaml" \
  -f "${CHART_PATH}/values-us.yaml" \
  --namespace "${NAMESPACE}" \
  --set image.tag="${IMAGE_TAG}" \
  --set replicaCount=1 \
  --set autoscaling.enabled=false \
  --set nameOverride="${CANARY_NAME}" \
  --set fullnameOverride="${CANARY_NAME}" \
  --set ingress.enabled=true \
  --set "ingress.annotations.nginx\.ingress\.kubernetes\.io/canary=true" \
  --set "ingress.annotations.nginx\.ingress\.kubernetes\.io/canary-weight=${CANARY_WEIGHT}" \
  --wait \
  --timeout 180s

echo "--- :white_check_mark: Canary deployed — ${CANARY_WEIGHT}% of traffic routed to new version"

# Add Buildkite annotation for visibility
buildkite-agent annotate --style "warning" --context "canary" \
  ":canary: Canary active — **${CANARY_WEIGHT}%** of US traffic on \`${IMAGE_TAG:0:8}\`" 2>/dev/null || true
