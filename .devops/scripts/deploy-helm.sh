#!/bin/bash

# Deploy Trifle to Kubernetes using Helm
# Usage: ./deploy-helm.sh [release-name] [namespace] [values-file]

set -e

RELEASE_NAME=${1:-trifle}
NAMESPACE=${2:-default}
VALUES_FILE=${3:-values-production.yaml}
CHART_PATH="$(dirname "$0")/../kubernetes/helm/trifle"

echo "Deploying Trifle with Helm..."
echo "Release: ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Values file: ${VALUES_FILE}"

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add required Helm repositories
echo "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install or upgrade the release
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Upgrading existing release..."
    helm upgrade "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --values "${CHART_PATH}/${VALUES_FILE}" \
        --wait \
        --timeout 600s
else
    echo "Installing new release..."
    helm install "${RELEASE_NAME}" "${CHART_PATH}" \
        --namespace "${NAMESPACE}" \
        --values "${CHART_PATH}/${VALUES_FILE}" \
        --wait \
        --timeout 600s
fi

echo "Deployment completed successfully!"

# Show status
echo "Release status:"
helm status "${RELEASE_NAME}" -n "${NAMESPACE}"

echo "Pods:"
kubectl get pods -l app.kubernetes.io/name=trifle -n "${NAMESPACE}"