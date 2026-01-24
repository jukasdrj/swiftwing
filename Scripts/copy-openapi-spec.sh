#!/bin/bash

# copy-openapi-spec.sh
# Copies the committed OpenAPI spec to the Generated directory for build
# Runs during each build - reads from committed spec (offline-capable, deterministic)
# Replaces fetch-openapi-spec.sh which downloaded remotely

set -e  # Exit immediately if any command fails

# Configuration
SOURCE_SPEC="${SRCROOT}/swiftwing/OpenAPI/talaria-openapi.yaml"
OUTPUT_DIR="${SRCROOT}/swiftwing/Generated"
OUTPUT_FILE="${OUTPUT_DIR}/openapi.yaml"

# Create Generated directory if it doesn't exist
if [ ! -d "${OUTPUT_DIR}" ]; then
    mkdir -p "${OUTPUT_DIR}"
fi

# Verify source spec exists
if [ ! -f "${SOURCE_SPEC}" ]; then
    echo "❌ ERROR: Committed OpenAPI spec not found"
    echo "   Expected: ${SOURCE_SPEC}"
    echo "   Run: scripts/update-api-spec.sh to fetch initial spec"
    exit 1
fi

# Copy spec to Generated directory
cp "${SOURCE_SPEC}" "${OUTPUT_FILE}"

# Silent success (minimal build output)
# Only show size for verification
SIZE=$(wc -c < "${OUTPUT_FILE}" | xargs)
echo "✅ OpenAPI spec ready (${SIZE} bytes)"
