#!/bin/bash

# Script to retrieve the auto-generated GeoServer admin password
# Usage: ./get-admin-password.sh [release-name] [namespace]

RELEASE_NAME=${1:-geoserver}
NAMESPACE=${2:-default}

echo "Retrieving GeoServer admin password for release: $RELEASE_NAME in namespace: $NAMESPACE"
echo "================================================================"

# Check if the secret exists
if kubectl get secret "${RELEASE_NAME}-admin" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Admin Username:"
    kubectl get secret "${RELEASE_NAME}-admin" -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 --decode
    echo
    echo
    echo "Admin Password:"
    kubectl get secret "${RELEASE_NAME}-admin" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 --decode
    echo
    echo
    echo "You can also export these credentials as environment variables:"
    echo "export GEOSERVER_ADMIN_USER=\$(kubectl get secret ${RELEASE_NAME}-admin -n $NAMESPACE -o jsonpath='{.data.username}' | base64 --decode)"
    echo "export GEOSERVER_ADMIN_PASSWORD=\$(kubectl get secret ${RELEASE_NAME}-admin -n $NAMESPACE -o jsonpath='{.data.password}' | base64 --decode)"
else
    echo "ERROR: Admin secret '${RELEASE_NAME}-admin' not found in namespace '$NAMESPACE'"
    echo
    echo "Available secrets in namespace '$NAMESPACE':"
    kubectl get secrets -n "$NAMESPACE" | grep "$RELEASE_NAME"
    
    echo
    echo "If you're using manual admin credentials, check your values.yaml configuration."
    echo "If you're using auto-generated passwords, ensure the admin-secret-generator job has completed successfully."
    exit 1
fi
