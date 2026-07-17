#!/bin/bash

# fetch-openapi-spec.sh
# Legacy build-phase helper (superseded by copy-openapi-spec.sh + committed spec).
# Kept for local/manual use. Downloads live contract from /v3/openapi.json.
#
# Live contract (Talaria 3.9.0+): GET https://api.oooefam.net/v3/openapi.json
# Historical path /openapi.yaml returns 404.

set -e  # Exit immediately if any command fails

# Configuration
SPEC_URL="https://api.oooefam.net/v3/openapi.json"
OUTPUT_DIR="${SRCROOT:-.}/swiftwing/Generated"
OUTPUT_FILE="${OUTPUT_DIR}/openapi.yaml"
TEMP_JSON="${OUTPUT_DIR}/.openapi.json.tmp"
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

echo "⬇️  Downloading JSON spec (timeout: ${TIMEOUT}s)..."

if curl --fail --silent --show-error \
    --max-time "${TIMEOUT}" \
    --user-agent "${USER_AGENT}" \
    -o "${TEMP_JSON}" \
    "${SPEC_URL}"; then
    if ! python3 - "${TEMP_JSON}" "${OUTPUT_FILE}" <<'PY'
import json, sys
from pathlib import Path
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML required: python3 -m pip install pyyaml\n")
    sys.exit(1)
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
spec = json.loads(src.read_text())
with dst.open("w") as f:
    yaml.dump(spec, f, sort_keys=False, default_flow_style=False, allow_unicode=True, width=100)
PY
    then
        rm -f "${TEMP_JSON}"
        echo "❌ Failed to convert OpenAPI JSON to YAML"
        exit 1
    fi
    rm -f "${TEMP_JSON}"
    echo "✅ OpenAPI spec fetched successfully"
    echo "   Size: $(wc -c < "${OUTPUT_FILE}" | xargs) bytes"
    exit 0
else
    # Check if a local spec already exists (for development when server is down)
    if [ -f "${OUTPUT_FILE}" ]; then
        echo "⚠️  Failed to fetch from ${SPEC_URL}"
        echo "   Using existing local spec for development"
        echo "   Size: $(wc -c < "${OUTPUT_FILE}" | xargs) bytes"
        echo "   WARNING: Build is using potentially stale API contract"
        exit 0
    else
        echo "❌ Failed to fetch OpenAPI spec from ${SPEC_URL}"
        echo "   Prefer committed spec via Scripts/copy-openapi-spec.sh"
        echo "   Docs: https://api.oooefam.net/v3/docs"
        exit 1
    fi
fi
