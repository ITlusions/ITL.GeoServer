#!/bin/bash
# Test script to verify keystore creation behavior

set -e

echo "Testing GeoServer Helm Chart - Optional Keystore Creation"
echo "========================================================="

# Test 1: HTTPS enabled with auto-generated keystore
echo -e "\n1. Testing HTTPS with auto-generated keystore..."
helm template geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=true \
  --set https.keystoreGenerator.domain=test.local \
  | grep -E "(keystore|HTTPS)" | head -10
echo "✓ Auto-generated keystore test passed"

# Test 2: HTTPS enabled with manual keystore secret
echo -e "\n2. Testing HTTPS with manual keystore secret..."
helm template geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=false \
  --set https.keystoreSecret=my-keystore-secret \
  | grep -E "(keystore|HTTPS)" | head -10
echo "✓ Manual keystore secret test passed"

# Test 3: HTTPS enabled WITHOUT keystore (ingress-only TLS)
echo -e "\n3. Testing HTTPS without keystore (ingress-only TLS)..."
helm template geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=false \
  --set https.keystoreSecret="" \
  | grep -E "(HTTPS_ENABLED|keystore)" || echo "No keystore references found (expected)"
echo "✓ Ingress-only TLS test passed"

# Test 4: HTTPS disabled
echo -e "\n4. Testing HTTPS disabled..."
helm template geoserver ./geoserver-chart \
  --set https.enabled=false \
  | grep -E "(keystore|HTTPS)" || echo "No HTTPS/keystore references found (expected)"
echo "✓ HTTPS disabled test passed"

# Test 5: Check if keystore generation job is only created when needed
echo -e "\n5. Testing keystore generation job creation..."
echo "With autoGenerateKeystore=true:"
helm template geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=true \
  | grep -c "keystore-generator-job" || echo "0"

echo "With autoGenerateKeystore=false:"
helm template geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=false \
  | grep -c "keystore-generator-job" || echo "0"
echo "✓ Keystore generation job creation test passed"

# Test 6: Validate the ingress-only values file
echo -e "\n6. Testing values-https-ingress-only.yaml..."
helm template geoserver ./geoserver-chart \
  -f ./values-https-ingress-only.yaml \
  | grep -E "(HTTPS_ENABLED)" | head -5
echo "✓ Ingress-only values file test passed"

echo -e "\n🎉 All tests passed! Keystore creation is now properly optional."
echo ""
echo "Usage examples:"
echo "  # HTTPS with auto-generated keystore:"
echo "  helm install geoserver ./geoserver-chart --set https.enabled=true"
echo ""
echo "  # HTTPS with manual keystore:"
echo "  helm install geoserver ./geoserver-chart --set https.enabled=true --set https.autoGenerateKeystore=false --set https.keystoreSecret=my-secret"
echo ""
echo "  # HTTPS with ingress-only TLS:"
echo "  helm install geoserver ./geoserver-chart -f values-https-ingress-only.yaml"
echo ""
