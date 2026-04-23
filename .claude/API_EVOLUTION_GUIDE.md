# API Contract Evolution Guide

## Overview

This guide explains how Swiftwing handles Talaria API schema evolution and provides strategies for maintaining forward-compatibility as the API contract changes.

## Key Principles

### 1. API Contract Boundary (CRITICAL)

The Talaria API defines an **external contract** that may differ from the internal **canonical models**:

- **External Contract:** The JSON structure returned by Talaria endpoints (e.g., `author: String`, `streamUrl: URL`)
- **Internal Canonical Models:** The internal data representation (e.g., `authors: [String]`, plural forms)
- **Swiftwing Strategy:** Map the external contract to internal models, accepting both old and new formats for smooth transitions

### 2. Versioning Strategy (No Explicit Versions)

Talaria does not use explicit API versions in the v3 endpoints. Instead, the schema evolves while maintaining backward-compatibility:

- Swiftwing must accept **both** old and new field names/types
- New fields are optional and default to sensible values
- Deprecated fields remain in responses for a transition period

### 3. Resilient Decoding (Mandatory Pattern)

```swift
// ✅ CORRECT: Resilient decoding prevents field corruption from failing entire parse
confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)
coverUrl = try? container.decodeIfPresent(URL.self, forKey: .coverUrl)

// ❌ WRONG: Will fail entire book decode if one field is malformed
confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
```

## Handling Schema Changes

### Scenario 1: New Required Field Appears

**Talaria adds a new field that Swiftwing doesn't know about:**

```swift
// Old API response
{ "jobId": "...", "streamUrl": "...", "status": "initialized" }

// New API response (adds newField)
{ "jobId": "...", "streamUrl": "...", "status": "initialized", "newField": "value" }

// Swiftwing decoder: Just ignore it (Codable ignores unknown fields by default)
// No changes needed!
```

### Scenario 2: Existing Field Changes Type

**Talaria changes `publicationYear: Int` to `publishedDate: String`:**

```swift
// Try both formats in priority order
if let year = try? container.decodeIfPresent(Int.self, forKey: .publicationYear) {
    publishedDate = "\(year)-01-01"
} else if let date = try? container.decodeIfPresent(String.self, forKey: .publishedDate) {
    publishedDate = date
} else {
    publishedDate = nil
}
```

### Scenario 3: Singular Field Becomes Plural

**Talaria changes `author: String` to `authors: [String]`:**

```swift
// Accept both formats
let authorString = try container.decodeIfPresent(String.self, forKey: .author)
if let a = authorString {
    author = a  // Prefer singular if present
} else if let authorsArray = try? container.decodeIfPresent([String].self, forKey: .authors) {
    author = authorsArray.joined(separator: ", ")  // Join plural
} else {
    author = nil
}
```

### Scenario 4: New Status Values Appear

**Talaria adds new `EnrichmentStatus` values:**

```swift
// Decoder defaults to .pending for unknown values
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = EnrichmentStatus(rawValue: rawValue) ?? .pending  // Graceful fallback
}
```

## Testing Strategy

### Contract Validation (CI-Safe)

Use fixtures to validate against **all known API versions**:

```swift
// swiftwingTests/Fixtures/TalariaContractFixtures.swift
enum TalariaContractFixtures {
    // Current format (v3.5.0)
    static let uploadResponseJSON = """
    { "jobId": "...", "status": "initialized", "streamUrl": "...", "token": null }
    """
    
    // Future format (hypothetical)
    static let uploadResponseFutureJSON = """
    { "jobId": "...", "status": "initialized", "streamUrl": "...", "token": null, "newField": "value" }
    """
}
```

### Adherence Tests

Write tests for **each version** you support:

```swift
final class TalariaContractAdherenceTests: XCTestCase {
    func test_decodeUploadResponse_withCurrentSchema() throws {
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseJSON)
        XCTAssertEqual(response.data.status, .initialized)
    }
    
    func test_decodeUploadResponse_withFutureSchema_ignoringNewFields() throws {
        // Should not fail when new fields are present
        let response = try TalariaContractFixtures.decodeUploadResponse(from: TalariaContractFixtures.uploadResponseFutureJSON)
        XCTAssertNotNil(response.data.jobId)
    }
}
```

## Common Pitfalls

### ❌ Hard-Coded Field Assumptions

```swift
// BAD: Assumes field will always exist
let title = try container.decode(String.self, forKey: .title)  // Fails if title is nil

// GOOD: Use optional decoding
let title = try container.decodeIfPresent(String.self, forKey: .title)
```

### ❌ Ignoring Unknown Values

```swift
// BAD: Crashes on unknown EnrichmentStatus
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = EnrichmentStatus(rawValue: rawValue)!  // Crashes if unknown
}

// GOOD: Default to safe value
self = EnrichmentStatus(rawValue: rawValue) ?? .pending
```

### ❌ Type Assumptions

```swift
// BAD: Assumes confidence is always Double
let confidence = try container.decode(Double.self, forKey: .confidence)  // Fails if string

// GOOD: Resilient decoding
let confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)  // Graceful
```

## Deprecation Timeline (When API Removes Old Format)

**Scenario:** Talaria wants to remove the old `author: String` field and migrate to `authors: [String]`

**Phase 1 (Dual format — current):**
- Talaria sends both `author` and `authors` in every response
- Swiftwing prefers `author` if present (backward-compatible)
- Swiftwing supports `authors` fallback

**Phase 2 (Transition — 2-3 months):**
- Talaria announces deprecation of `author` field
- Sends new field `authors` while keeping `author` for compatibility
- Swiftwing already supports both; no changes needed

**Phase 3 (Removal — 6 months after announcement):**
- Talaria removes `author` field entirely
- Swiftwing switches to preferring `authors`
- Fallback to `author` is no longer needed but kept for safety

## Monitoring Contract Changes

### Automated Detection

In `TalariaService`, log warnings when **unexpected schema changes** are detected:

```swift
// Log if response doesn't have expected fields for current version
if !uploadResponse.data.streamUrl.absoluteString.starts(with: "https://") {
    e2eLogger.warning("Unexpected streamUrl format")
}

// Log if status field is missing (would indicate old API version)
if uploadResponse.data.status == nil {
    e2eLogger.warning("Missing status field — may indicate old Talaria API version")
}
```

### Manual Review

**Before committing OpenAPI spec changes:**

```bash
# Review what changed
git diff swiftwing/OpenAPI/talaria-openapi.yaml

# Key things to check:
# 1. New required fields? Add default values
# 2. Fields that changed type? Add try/catch fallback
# 3. New enum values? Add graceful fallback
# 4. Removed fields? Update decoders to use optional
```

## Decision Tree: When Schema Changes

```
Does Talaria add a new field?
├─ Yes, required for functionality → Add optional decoding with sensible default
├─ Yes, optional → Ignore (Codable handles it)
└─ No

Does Talaria remove a field?
├─ Yes → Update decoder to use optional (try?)
└─ No

Does Talaria change field type?
├─ Yes → Add try/catch for both old and new types
└─ No

Does Talaria add new enum values?
├─ Yes → Add default fallback in decoder
└─ No

Does Talaria change field name (e.g., author → authors)?
├─ Yes → Try both names, prefer old for backward-compat
└─ No
```

## Maintenance Checklist

When Talaria releases a new API version:

- [ ] Download latest OpenAPI spec: `./Scripts/update-api-spec.sh`
- [ ] Review changes: `git diff swiftwing/OpenAPI/`
- [ ] Add fixtures for new format: `TalariaContractFixtures.swift`
- [ ] Write tests for new fields: `TalariaContractAdherenceTests.swift`
- [ ] Update decoders with fallbacks (if needed)
- [ ] Run tests: `xcodebuild ... test`
- [ ] Update CLAUDE.md with new endpoints/fields
- [ ] Commit with message: `chore: align Swiftwing to Talaria API v3.X.X`

## Resources

- **Talaria OpenAPI Spec:** `swiftwing/OpenAPI/talaria-openapi.yaml`
- **Contract Fixtures:** `swiftwingTests/Fixtures/TalariaContractFixtures.swift`
- **Adherence Tests:** `swiftwingTests/Unit/Services/TalariaContractAdherenceTests.swift`
- **NetworkTypes:** `swiftwing/Services/NetworkTypes.swift` (decoders)
- **Talaria Docs:** `https://api.oooefam.net/docs`
- **Talaria GitHub:** `https://github.com/jukasdrj/talaria`

---

**Last Updated:** April 2026  
**Version:** 1.0.0  
**Maintained By:** Swiftwing Team (@juju)
