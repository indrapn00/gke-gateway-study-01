#!/usr/bin/env bash
# Lab 0 - create the lab infrastructure (CLI fallback for the Console steps in hands-on-lab.md):
#   1. VPC (custom mode)
#   2. Node subnet with secondary ranges for Pods and Services
#   3. Proxy-only subnet (needed by regional / internal Gateways)
#   4. GKE Autopilot cluster (Gateway API is always enabled on Autopilot)
#   5. kubectl credentials
# Safe to re-run: anything that already exists is skipped.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

exists() { "$@" >/dev/null 2>&1; }

echo "== [1/5] VPC ${VPC_NAME}"
if exists gcloud compute networks describe "${VPC_NAME}" --project="${PROJECT_ID}"; then
  echo "   already exists - skipped"
else
  gcloud compute networks create "${VPC_NAME}" \
    --project="${PROJECT_ID}" --subnet-mode=custom --bgp-routing-mode=regional
fi

echo "== [2/5] Node subnet ${SUBNET_NAME} (${SUBNET_RANGE}) + secondary ranges"
if exists gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}"; then
  echo "   already exists - skipped"
else
  gcloud compute networks subnets create "${SUBNET_NAME}" \
    --project="${PROJECT_ID}" --network="${VPC_NAME}" --region="${REGION}" \
    --range="${SUBNET_RANGE}" \
    --secondary-range="${POD_RANGE_NAME}=${POD_RANGE},${SVC_RANGE_NAME}=${SVC_RANGE}" \
    --enable-private-ip-google-access
fi

echo "== [3/5] Proxy-only subnet ${PROXY_SUBNET_NAME} (${PROXY_SUBNET_RANGE})"
if exists gcloud compute networks subnets describe "${PROXY_SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}"; then
  echo "   already exists - skipped"
else
  gcloud compute networks subnets create "${PROXY_SUBNET_NAME}" \
    --project="${PROJECT_ID}" --network="${VPC_NAME}" --region="${REGION}" \
    --range="${PROXY_SUBNET_RANGE}" --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
fi

echo "== [4/5] GKE Autopilot cluster ${CLUSTER_NAME} (takes ~5-10 minutes)"
if exists gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}"; then
  echo "   already exists - skipped"
else
  gcloud container clusters create-auto "${CLUSTER_NAME}" \
    --project="${PROJECT_ID}" --region="${REGION}" \
    --network="${VPC_NAME}" --subnetwork="${SUBNET_NAME}" \
    --cluster-secondary-range-name="${POD_RANGE_NAME}" \
    --services-secondary-range-name="${SVC_RANGE_NAME}" \
    --release-channel=regular
fi

echo "== [5/5] kubectl credentials"
gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}"

echo
echo "== GatewayClasses (if empty, wait a minute and run 'kubectl get gatewayclass' again)"
kubectl get gatewayclass || true
