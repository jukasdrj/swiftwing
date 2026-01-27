---
argument-hint: [--force]
model: haiku
allowed-tools:
  - Bash
---

# Update Talaria API Spec

Update OpenAPI spec from Talaria API{{#if $1}} with force flag{{/if}}

```bash
cd /Users/juju/dev_repos/swiftwing
./Scripts/update-api-spec.sh{{#if $1}} {{$1}}{{/if}}
```

**Spec Management**:
- ✅ Spec **committed** to repo (not fetched during build)
- ✅ SHA256 checksum verification
- ✅ Offline-capable builds
- ✅ Manual updates only

**Force Update** (`--force`):
- Bypasses checksum check
- Overwrites existing spec
- Use when Talaria API has breaking changes

**Location**: `swiftwing/OpenAPI/talaria-openapi.yaml`
**Source**: https://api.oooefam.net/v3/openapi.json
