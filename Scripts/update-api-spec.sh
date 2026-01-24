#!/bin/bash

# update-api-spec.sh
# Manual script to update the committed OpenAPI specification from Talaria server
# Requires explicit --force flag to overwrite existing spec
# Includes checksum verification for integrity

set -e  # Exit immediately if any command fails

# Configuration
SPEC_URL="https://api.oooefam.net/openapi.yaml"
SPEC_DIR="swiftwing/OpenAPI"
SPEC_FILE="${SPEC_DIR}/talaria-openapi.yaml"
TEMP_FILE="${SPEC_DIR}/.openapi.yaml.tmp"
CHECKSUM_FILE="${SPEC_DIR}/.talaria-openapi.yaml.sha256"
USER_AGENT="SwiftWing/1.0 (OpenAPI Manual Update)"
TIMEOUT=30

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage
usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Fetches the latest OpenAPI specification from Talaria server."
    echo ""
    echo "Options:"
    echo "  --force    Overwrite existing spec without confirmation"
    echo ""
    echo "The script will:"
    echo "  1. Download spec from ${SPEC_URL}"
    echo "  2. Verify download integrity"
    echo "  3. Show diff if spec exists"
    echo "  4. Require confirmation unless --force is used"
    echo "  5. Update checksum for verification"
    exit 1
}

# Parse arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Header
echo -e "${BLUE}📡 SwiftWing OpenAPI Spec Updater${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create directory if it doesn't exist
if [ ! -d "${SPEC_DIR}" ]; then
    echo -e "${YELLOW}📁 Creating ${SPEC_DIR} directory...${NC}"
    mkdir -p "${SPEC_DIR}"
fi

# Check if spec already exists
SPEC_EXISTS=false
if [ -f "${SPEC_FILE}" ]; then
    SPEC_EXISTS=true
    echo -e "${YELLOW}⚠️  Existing spec found${NC}"
    echo "   Path: ${SPEC_FILE}"
    echo "   Size: $(wc -c < "${SPEC_FILE}" | xargs) bytes"
    echo ""
fi

# Fetch the spec to temporary file
echo -e "${BLUE}⬇️  Downloading OpenAPI spec...${NC}"
echo "   URL: ${SPEC_URL}"
echo "   Timeout: ${TIMEOUT}s"
echo ""

if ! curl --fail --silent --show-error \
    --max-time "${TIMEOUT}" \
    --user-agent "${USER_AGENT}" \
    -o "${TEMP_FILE}" \
    "${SPEC_URL}"; then
    echo -e "${RED}❌ Failed to fetch OpenAPI spec from ${SPEC_URL}${NC}"
    echo "   Check network connectivity and server availability"
    rm -f "${TEMP_FILE}"
    exit 1
fi

# Verify download succeeded and has content
if [ ! -s "${TEMP_FILE}" ]; then
    echo -e "${RED}❌ Downloaded file is empty${NC}"
    rm -f "${TEMP_FILE}"
    exit 1
fi

# Calculate checksum of downloaded file
DOWNLOADED_SIZE=$(wc -c < "${TEMP_FILE}" | xargs)
DOWNLOADED_SHA256=$(shasum -a 256 "${TEMP_FILE}" | awk '{print $1}')

echo -e "${GREEN}✅ Download successful${NC}"
echo "   Size: ${DOWNLOADED_SIZE} bytes"
echo "   SHA256: ${DOWNLOADED_SHA256}"
echo ""

# Compare with existing spec if it exists
if [ "${SPEC_EXISTS}" = true ]; then
    # Calculate existing checksum
    EXISTING_SHA256=$(shasum -a 256 "${SPEC_FILE}" | awk '{print $1}')

    if [ "${DOWNLOADED_SHA256}" = "${EXISTING_SHA256}" ]; then
        echo -e "${GREEN}✓ Spec is unchanged (checksums match)${NC}"
        echo "   No update needed"
        rm -f "${TEMP_FILE}"
        exit 0
    fi

    echo -e "${YELLOW}⚠️  Spec has changed${NC}"
    echo "   Old SHA256: ${EXISTING_SHA256}"
    echo "   New SHA256: ${DOWNLOADED_SHA256}"
    echo ""

    # Show diff
    echo -e "${BLUE}📊 Changes preview:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Show a concise diff (first 50 lines)
    if command -v diff &> /dev/null; then
        diff -u "${SPEC_FILE}" "${TEMP_FILE}" | head -50 || true
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi

    # Require confirmation unless --force
    if [ "${FORCE}" = false ]; then
        echo -e "${YELLOW}⚠️  This will overwrite the existing spec${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}ℹ️  Update cancelled${NC}"
            rm -f "${TEMP_FILE}"
            exit 0
        fi
    else
        echo -e "${YELLOW}⚡ --force flag set, updating without confirmation${NC}"
    fi
fi

# Move temp file to final location
mv "${TEMP_FILE}" "${SPEC_FILE}"

# Save checksum
echo "${DOWNLOADED_SHA256}  talaria-openapi.yaml" > "${CHECKSUM_FILE}"

echo ""
echo -e "${GREEN}✅ OpenAPI spec updated successfully${NC}"
echo "   Path: ${SPEC_FILE}"
echo "   Size: ${DOWNLOADED_SIZE} bytes"
echo "   Checksum: ${CHECKSUM_FILE}"
echo ""
echo -e "${BLUE}📝 Next steps:${NC}"
echo "   1. Review the changes: git diff ${SPEC_FILE}"
echo "   2. Rebuild the project to regenerate client code"
echo "   3. Test the integration with updated API"
echo "   4. Commit if changes are intentional:"
echo "      git add ${SPEC_FILE} ${CHECKSUM_FILE}"
echo "      git commit -m 'chore: Update Talaria OpenAPI spec'"
echo ""
