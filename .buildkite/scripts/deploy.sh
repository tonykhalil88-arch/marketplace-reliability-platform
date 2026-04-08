#!/usr/bin/env bash
# ─── Helm Deploy Script ─────────────────────────────────────────────────────
# Deploys the product catalog service to a Kubernetes cluster via Helm.
# Called by the Buildkite pipeline with environment variables.
#
# Required env vars:
#   DEPLOY_ENV    - Environment name (staging, production)
#   DEPLOY_REGION - AWS region (us-east-1, ap-southeast-2)
#   IMAGE_TAG     - Docker image tag (usually git commit SHA)
#   HELM_VALUES   - Comma-separated list of values files
#   NAMESPACE     - Kubernetes namespace
#
# Optional env vars:
#   KUBECONFIG_CONTEXT - kubectl context to use (defaults to current)
#   HELM_TIMEOUT       - Timeout for helm upgrade (default: 300s)

set -euo pipefail

SERVICE_NAME="product-catalog"
CHART_PATH="./helm-chart"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

echo "--- :kubernetes: Deploying ${SERVICE_NAME} to ${DEPLOY_ENV} (${DEPLOY_REGION})"
echo "Image tag: ${IMAGE_TAG}"
echo "Values files: ${HELM_VALUES}"

# Switch kubectl context if specified (for multi-region deploys)
if [[ -n "${KUBECONFIG_CONTEXT:-}" ]]; then
  echo "Switching to kubectl context: ${KUBECONFIG_CONTEXT}"
  kubectl config use-context "${KUBECONFIG_CONTEXT}"
fi

# Build the values file arguments
VALUES_ARGS=""
IFS=',' read -ra VALUES_FILES <<< "${HELM_VALUES}"
for vf in "${VALUES_FILES[@]}"; do
  VALUES_ARGS="${VALUES_ARGS} -f ${CHART_PATH}/${vf}"
done

# Record deploy start time for Datadog deploy tracking
DEPLOY_START=$(date +%s)

# Annotate Buildkite build with deploy info
buildkite-agent annotate --style "info" --context "deploy-${DEPLOY_REGION}" \
  "Deploying \`${IMAGE_TAG:0:8}\` to **${DEPLOY_ENV}** (${DEPLOY_REGION})" 2>/dev/null || true

# Execute Helm upgrade
echo "--- :helm: Running helm upgrade"
helm upgrade --install "${SERVICE_NAME}" "${CHART_PATH}" \
  ${VALUES_ARGS} \
  --namespace "${NAMESPACE}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.region="${DEPLOY_REGION}" \
  --wait \
  --timeout "${HELM_TIMEOUT}" \
  --atomic  # Automatically rollback on failure

DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END - DEPLOY_START))

echo "--- :white_check_mark: Deploy completed in ${DEPLOY_DURATION}s"

# Send deploy event to Datadog for correlation with metrics
# This creates a vertical line on dashboards showing when deploys happened
echo "--- :datadog: Sending deploy event to Datadog"
curl -s -X POST "https://api.datadoghq.com/api/v1/events" \
  -H "DD-API-KEY: ${DD_API_KEY:-}" \
  -H "Content-Type: application/json" \
  -d @- <<EOF || true
{
  "title": "${SERVICE_NAME} deployed to ${DEPLOY_ENV} (${DEPLOY_REGION})",
  "text": "Version: ${IMAGE_TAG}\nDuration: ${DEPLOY_DURATION}s\nBuild: ${BUILDKITE_BUILD_URL:-unknown}",
  "tags": [
    "service:${SERVICE_NAME}",
    "environment:${DEPLOY_ENV}",
    "region:${DEPLOY_REGION}",
    "version:${IMAGE_TAG}",
    "team:platform"
  ],
  "alert_type": "info",
  "source_type_name": "buildkite"
}
EOF

# Verify the rollout status
echo "--- :eyes: Verifying rollout"
kubectl rollout status deployment/${SERVICE_NAME} \
  --namespace "${NAMESPACE}" \
  --timeout=120s

echo "--- :tada: Deploy to ${DEPLOY_ENV} (${DEPLOY_REGION}) successful"
