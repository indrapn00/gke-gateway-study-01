#!/usr/bin/env bash
# Lab 5 - clean up everything, in the safe order (CLI fallback for the Console steps):
#   1. Kubernetes objects that own load balancers (so GKE removes the load balancers cleanly)
#   2. Wait until the generated load balancers are gone
#   3. Cloud Armor policy
#   4. GKE cluster
#   5. Subnets and VPC
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
if ask "Delete all lab Kubernetes objects in cluster ${CLUSTER_NAME}?"; then
  gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" || true
  kubectl delete -f "${M}/lab4-internal-gateway/" --ignore-not-found
  kubectl delete -f "${M}/lab3-policies/" --ignore-not-found
  kubectl delete -f "${M}/lab2-shared-gateway/" --ignore-not-found
  kubectl delete -f "${M}/lab1-three-doors/" --ignore-not-found
fi

echo "== [2/5] Waiting for GKE to remove the generated load balancers (forwarding rules)"
for _ in $(seq 1 60); do
  left="$(gcloud compute forwarding-rules list --project="${PROJECT_ID}" \
    --filter="name~^gkegw1- OR name~^k8s2- OR description~lab1-three-doors" --format="value(name)" 2>/dev/null)"
  [[ -z "${left}" ]] && { echo "   all gone"; break; }
  echo "   still there: $(echo "${left}" | tr '\n' ' ')"; sleep 10
done

echo "== [3/5] Cloud Armor policy ${ARMOR_POLICY}"
if gcloud compute security-policies describe "${ARMOR_POLICY}" --project="${PROJECT_ID}" >/dev/null 2>&1 \
   && ask "Delete Cloud Armor policy ${ARMOR_POLICY}?"; then
  gcloud compute security-policies delete "${ARMOR_POLICY}" --project="${PROJECT_ID}" --quiet
fi

echo "== [4/5] GKE cluster ${CLUSTER_NAME}"
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1 \
   && ask "Delete GKE cluster ${CLUSTER_NAME}?"; then
  gcloud container clusters delete "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet
fi

echo "== [5/5] Subnets and VPC ${VPC_NAME}"
if ask "Delete subnets ${PROXY_SUBNET_NAME}, ${SUBNET_NAME} and VPC ${VPC_NAME}?"; then
  gcloud compute networks subnets delete "${PROXY_SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
  gcloud compute networks subnets delete "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
  echo "   firewall rules still attached to ${VPC_NAME} (delete them if the VPC delete fails):"
  gcloud compute firewall-rules list --project="${PROJECT_ID}" --filter="network~${VPC_NAME}" --format="value(name)" || true
  gcloud compute networks delete "${VPC_NAME}" --project="${PROJECT_ID}" --quiet || true
fi

echo "Done."
