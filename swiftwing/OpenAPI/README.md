# OpenAPI Specification Management

This directory contains the committed OpenAPI specification for the Talaria backend API.

## Files

| File | Purpose |
|------|---------|
| `talaria-openapi.yaml` | Committed OpenAPI 3.0 specification |
| `.talaria-openapi.yaml.sha256` | SHA256 checksum for integrity verification |

## Philosophy: Committed Specs for Deterministic Builds

SwiftWing uses a **committed specification** approach rather than auto-fetching during builds.

### Benefits

**Deterministic Builds:**
- Same source code → same binary output
- No surprises from upstream API changes
- Reproducible builds across all environments

**Offline Development:**
- No internet required to build
- Works in air-gapped environments
- Fast builds (no network latency)

**Security:**
- Prevents supply chain attacks
- No runtime fetching of untrusted specs
- All changes go through code review

**Version Control:**
- Full history of API evolution
- Easy rollback to previous versions
- Team visibility into API changes

**CI/CD Reliability:**
- No external dependencies
- Builds don't fail due to network issues
- Predictable build times

## Updating the Specification

### Manual Update Workflow

**When to Update:**
- Talaria API adds new endpoints
- API changes request/response schemas
- Deprecated features are removed
- New optional fields added

**Update Process:**

1. **Fetch Latest Spec**
   ```bash
   # From project root
   ./Scripts/update-api-spec.sh
   ```

2. **Review Changes**
   ```bash
   git diff swiftwing/OpenAPI/talaria-openapi.yaml
   ```

   **Look for:**
   - ✅ New endpoints (additions are usually safe)
   - ⚠️ Removed endpoints (breaking change)
   - ⚠️ Changed request/response schemas (may break code)
   - ✅ New optional fields (safe)
   - ⚠️ Required fields removed (breaking change)

3. **Test Changes**
   ```bash
   # Rebuild project
   xcodebuild -project swiftwing.xcodeproj -scheme swiftwing \
     -sdk iphonesimulator \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
     clean build 2>&1 | xcsift

   # Run integration tests
   xcodebuild test \
     -only-testing:swiftwingTests/TalariaIntegrationTests \
     2>&1 | xcsift
   ```

4. **Update Code If Necessary**
   - If spec changes affect TalariaService, update implementation
   - Update NetworkTypes.swift if schemas changed
   - Adjust SSE event parsing if event types changed

5. **Commit Changes**
   ```bash
   git add swiftwing/OpenAPI/
   git commit -m "chore: Update Talaria OpenAPI spec

   Changes:
   - Added new field: bookMetadata.publishedDate
   - Deprecated: bookMetadata.publicationYear (use publishedDate)

   Tested with TalariaIntegrationTests - all pass."
   ```

### Script Details: update-api-spec.sh

**Location:** `Scripts/update-api-spec.sh`

**Usage:**
```bash
# Interactive mode (requires confirmation)
./Scripts/update-api-spec.sh

# Force mode (overwrites without confirmation)
./Scripts/update-api-spec.sh --force
```

**What It Does:**
1. Fetches latest spec from Talaria server
2. Computes SHA256 checksum
3. Shows diff preview
4. Asks for confirmation (unless `--force`)
5. Updates both files atomically
6. Verifies checksum integrity

**Safety Features:**
- Requires `--force` flag to overwrite existing spec
- Shows full diff before updating
- Verifies checksum after update
- Preserves backup if update fails

**Environment Variables:**
```bash
# Override Talaria API endpoint
TALARIA_API_BASE_URL=https://staging.oooefam.net ./Scripts/update-api-spec.sh
```

## Build Integration

### copy-openapi-spec.sh

**Purpose:** Copies committed spec to Generated/ during build

**Location:** `Scripts/copy-openapi-spec.sh`

**Build Phase:** "Run Script" (before "Compile Sources")

**Script:**
```bash
#!/bin/bash
set -e

SPEC_SRC="$SRCROOT/swiftwing/OpenAPI/talaria-openapi.yaml"
SPEC_DST="$SRCROOT/swiftwing/Generated/openapi.yaml"

# Create Generated directory
mkdir -p "$SRCROOT/swiftwing/Generated"

# Copy spec
cp "$SPEC_SRC" "$SPEC_DST"

echo "✅ Copied OpenAPI spec to Generated/"
```

**Why This Exists:**
- Swift OpenAPI Generator expects spec in Generated/ (if using plugin)
- Keeps committed spec in OpenAPI/ for clarity
- Generated/ is .gitignored (ephemeral build artifacts)

## Verification

### Checksum Validation

**Purpose:** Ensure spec hasn't been corrupted

**Manual Check:**
```bash
cd swiftwing/OpenAPI

# Compute current checksum
shasum -a 256 talaria-openapi.yaml

# Compare to stored checksum
cat .talaria-openapi.yaml.sha256
```

**Expected:** Both values should match exactly

**If Mismatch:**
- File may be corrupted
- Manual edits may have been made
- Re-run `update-api-spec.sh --force` to fix

### Spec Validation

**YAML Syntax:**
```bash
# Using Python
python3 -c "import yaml; yaml.safe_load(open('swiftwing/OpenAPI/talaria-openapi.yaml'))"

# Using yq (if installed)
yq eval '.' swiftwing/OpenAPI/talaria-openapi.yaml > /dev/null
```

**OpenAPI Compliance:**
```bash
# Using openapi-generator-cli (if installed)
openapi-generator-cli validate -i swiftwing/OpenAPI/talaria-openapi.yaml
```

## Rollback Procedures

See [CLAUDE.md - Rollback Procedures](../../CLAUDE.md#rollback-procedures) for detailed steps.

**Quick Rollback:**
```bash
# Undo uncommitted changes
git checkout swiftwing/OpenAPI/

# Rollback to specific version
git checkout <commit-hash> -- swiftwing/OpenAPI/

# Rollback to previous commit
git checkout HEAD~1 -- swiftwing/OpenAPI/
```

## Future: Auto-Generated Client

**Current State:** SwiftWing uses manual TalariaService implementation

**Future Enhancement:** Enable swift-openapi-generator build plugin

**Steps:**
1. Open `swiftwing.xcodeproj` in Xcode
2. Select `swiftwing` target → Build Phases
3. Add "Run Build Tool Plug-ins"
4. Select "OpenAPIGenerator" plugin
5. Create `openapi-generator-config.yaml`
6. Rebuild project
7. Generated code appears in `swiftwing/Generated/`

**See:** [CLAUDE.md - Swift OpenAPI Generator Integration](../../CLAUDE.md#swift-openapi-generator-integration)

## Troubleshooting

### "Spec file not found during build"

**Solution:**
```bash
# Verify file exists
ls -la swiftwing/OpenAPI/talaria-openapi.yaml

# Manually run copy script
bash Scripts/copy-openapi-spec.sh

# Check Generated directory
ls -la swiftwing/Generated/openapi.yaml
```

### "Checksum verification failed"

**Solution:**
```bash
# Re-compute checksum
shasum -a 256 swiftwing/OpenAPI/talaria-openapi.yaml > swiftwing/OpenAPI/.talaria-openapi.yaml.sha256

# Or re-fetch from server
./Scripts/update-api-spec.sh --force
```

### "Cannot connect to Talaria API"

**Cause:** API endpoint unreachable

**Check:**
```bash
# Test connectivity
curl -I https://api.oooefam.net

# Check VPN status (if behind firewall)
```

**Solution:**
- Ensure network connectivity
- Check if API requires VPN access
- Verify API is not down (check status page)

## References

- **OpenAPI Spec:** [OpenAPI 3.0 Specification](https://spec.openapis.org/oas/v3.0.0)
- **Swift OpenAPI Generator:** [GitHub Repository](https://github.com/apple/swift-openapi-generator)
- **Talaria API Docs:** Contact backend team for documentation
- **Integration Tests:** `swiftwingTests/TalariaIntegrationTests_README.md`

## Best Practices

**DO:**
- ✅ Review diffs before committing spec updates
- ✅ Run integration tests after updating spec
- ✅ Include changelog in commit message
- ✅ Verify checksum after manual edits
- ✅ Keep spec and code in sync

**DON'T:**
- ❌ Manually edit the spec without re-computing checksum
- ❌ Commit spec changes without testing
- ❌ Skip code review for spec updates
- ❌ Auto-update spec in CI/CD (defeats committed spec purpose)
- ❌ Delete checksum file (breaks verification)

## Questions?

- **Spec update issues:** Check `Scripts/update-api-spec.sh` script logs
- **Build integration:** See `Scripts/copy-openapi-spec.sh`
- **General OpenAPI questions:** See [CLAUDE.md](../../CLAUDE.md)
- **Integration testing:** See `swiftwingTests/TalariaIntegrationTests_README.md`
