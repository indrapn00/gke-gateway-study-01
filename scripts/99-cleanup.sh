#!/usr/bin/env bash
# Lab 5 - clean up everything, in the safe order (CLI fallback for the Console steps):
#   1. Kubernetes objects that own load balancers (so GKE removes the load balancers cleanly)
#   2. Wait until the generated load balancers are gone
#   3. Cloud Armor policy
#   4. GKE cluster
#   5. Leftover NEGs / firewall rules on the lab VPC, then subnets and VPC
# Asks before every delete. Use --yes to skip the questions.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

YES="${1:-}"
ask() {  # $1 = question
  [[ "${YES}" == "--yes" ]] && return 0
  read -r -p "$1 [y/N] " a; [[ "${a}" =~ ^[Yy]$ ]]
}

M="${REPO_ROOT}/manifests"

echo "== [1/5] Kubernetes objects (Gateways, routes, policies, Ingress, Services, apps)"
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  if ask "Delete all lab Kubernetes objects in cluster ${CLUSTER_NAME}?"; then
    gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
    kubectl delete -f "${M}/lab4-internal-gateway/" --ignore-not-found || true
    kubectl delete -f "${M}/lab3-policies/" --ignore-not-found || true
    kubectl delete -f "${M}/lab2-shared-gateway/" --ignore-not-found || true
    kubectl delete -f "${M}/lab1-three-doors/" --ignore-not-found || true
  fi
else
  echo "   cluster ${CLUSTER_NAME} does not exist - skipped"
fi

echo "== [2/5] Waiting for GKE to remove the generated load balancers (forwarding rules)"
for _ in $(seq 1 60); do
  left="$(gcloud compute forwarding-rules list --project="${PROJECT_ID}" \
    --filter="name~lab1-three-doors OR name~infra-ns OR description~lab1-three-doors OR description~infra-ns" \
    --format="value(name)" 2>/dev/null)"
  if [[ -z "${left}" ]]; then
    echo "   forwarding rules gone; waiting 15s for backend services / URL maps to finish deleting..."
    sleep 15
    break
  fi
  echo "   still there: $(echo "${left}" | tr '\n' ' ')"
  sleep 10
done

echo "== [3/5] Cloud Armor policy ${ARMOR_POLICY}"
if gcloud compute security-policies describe "${ARMOR_POLICY}" --project="${PROJECT_ID}" >/dev/null 2>&1 \
   && ask "Delete Cloud Armor policy ${ARMOR_POLICY}?"; then
  gcloud compute security-policies delete "${ARMOR_POLICY}" --project="${PROJECT_ID}" --quiet
fi

echo "== [4/5] GKE cluster ${CLUSTER_NAME} (takes ~3-6 minutes)"
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1 \
   && ask "Delete GKE cluster ${CLUSTER_NAME}?"; then
  gcloud container clusters delete "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet
fi

echo "== [5/5] Subnets and VPC ${VPC_NAME}"
if gcloud compute networks describe "${VPC_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1 \
   && ask "Delete leftover NEGs/firewall rules, subnets (${PROXY_SUBNET_NAME}, ${SUBNET_NAME}), and VPC ${VPC_NAME}?"; then

  # Remove any leftover zonal NEGs on the lab VPC so subnet deletion does not fail
  while IFS=, read -r neg_name neg_zone; do
    [[ -z "${neg_name}" || -z "${neg_zone}" ]] && continue
    echo "   deleting leftover NEG ${neg_name} (${neg_zone})..."
    gcloud compute network-endpoint-groups delete "${neg_name}" --zone="${neg_zone}" --project="${PROJECT_ID}" --quiet || true
  done < <(gcloud compute network-endpoint-groups list --project="${PROJECT_ID}" \
    --filter="network ~ /networks/${VPC_NAME}$" --format="csv[no-heading](name,zone.basename())" 2>/dev/null || true)

  # Remove any leftover firewall rules attached to the lab VPC so VPC deletion succeeds cleanly
  fw_rules="$(gcloud compute firewall-rules list --project="${PROJECT_ID}" \
    --filter="network ~ /networks/${VPC_NAME}$" --format="value(name)" 2>/dev/null || true)"
  if [[ -n "${fw_rules}" ]]; then
    echo "   deleting firewall rules on ${VPC_NAME}: $(echo "${fw_rules}" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    gcloud compute firewall-rules delete ${fw_rules} --project="${PROJECT_ID}" --quiet || true
  fi

  gcloud compute networks subnets delete "${PROXY_SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
  gcloud compute networks subnets delete "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
  gcloud compute networks delete "${VPC_NAME}" --project="${PROJECT_ID}" --quiet
fi

echo "Done. All lab resources for ${VPC_NAME} / ${CLUSTER_NAME} have been cleaned up."
