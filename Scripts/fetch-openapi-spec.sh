#!/bin/bash

# fetch-openapi-spec.sh
# Fetches the OpenAPI specification from Talaria server during each build
# Runs before compilation to ensure client stays synchronized with latest API contract

set -e  # Exit immediately if any command fails

# Configuration
SPEC_URL="https://api.oooefam.net/openapi.yaml"
OUTPUT_DIR="${SRCROOT}/swiftwing/Generated"
OUTPUT_FILE="${OUTPUT_DIR}/openapi.yaml"
USER_AGENT="SwiftWing/1.0 (OpenAPI Fetch)"
TIMEOUT=30

# Log start
echo "📡 Fetching OpenAPI spec from Talaria server..."
echo "   URL: ${SPEC_URL}"
echo "   Output: ${OUTPUT_FILE}"

# Create Generated directory if it doesn't exist
if [ ! -d "${OUTPUT_DIR}" ]; then
    echo "📁 Creating Generated directory..."
    mkdir -p "${OUTPUT_DIR}"
fi

# Fetch the OpenAPI spec
# --fail: Fail silently on HTTP errors (4xx, 5xx)
# --silent: Don't show progress meter
# --show-error: Show error message if it fails
# --max-time: Maximum time allowed for the transfer
# --user-agent: Set custom User-Agent header
# -o: Write output to file
echo "⬇️  Downloading spec (timeout: ${TIMEOUT}s)..."

if curl --fail --silent --show-error \
    --max-time "${TIMEOUT}" \
    --user-agent "${USER_AGENT}" \
    -o "${OUTPUT_FILE}" \
    "${SPEC_URL}"; then
    echo "✅ OpenAPI spec fetched successfully"
    echo "   Size: $(wc -c < "${OUTPUT_FILE}" | xargs) bytes"
    exit 0
else
    echo "❌ Failed to fetch OpenAPI spec from ${SPEC_URL}"
    echo "   Build cannot continue with stale API contract"
    echo "   Ensure network connectivity and server availability"
    exit 1
fi
