#!/usr/bin/env bash
# Central settings for the GKE Gateway study lab.
# Usage:  source scripts/env.sh
# Change PROJECT_ID / REGION here if you run the lab somewhere else.

# Ensure gcloud/kubectl are on PATH in non-login shells where the SDK lives in ~/google-cloud-sdk/bin
if ! command -v gcloud >/dev/null 2>&1 && [[ -d "${HOME}/google-cloud-sdk/bin" ]]; then
  export PATH="${HOME}/google-cloud-sdk/bin:${PATH}"
fi

export PROJECT_ID="gcp-demo-02-307713"
export REGION="asia-southeast2"                       # Jakarta

# Network
export VPC_NAME="gke-gw-study-vpc"
export SUBNET_NAME="gke-gw-study-subnet"
export SUBNET_RANGE="10.20.0.0/24"                    # node IPs (+ internal LB IPs)
export POD_RANGE_NAME="gke-gw-study-pods"
export POD_RANGE="10.21.0.0/17"                       # Pod IPs (secondary range)
export SVC_RANGE_NAME="gke-gw-study-services"
export SVC_RANGE="10.22.0.0/22"                       # Service ClusterIPs (secondary range)
export PROXY_SUBNET_NAME="gke-gw-study-proxy-only-subnet"
export PROXY_SUBNET_RANGE="10.20.2.0/23"              # Envoy proxies of regional/internal Application LBs

# Cluster
export CLUSTER_NAME="gke-gw-study-cluster"            # GKE Autopilot, Regular release channel

# Lab 3
export ARMOR_POLICY="gke-gw-study-armor"              # Cloud Armor backend security policy

# Repository root (works from any folder)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
