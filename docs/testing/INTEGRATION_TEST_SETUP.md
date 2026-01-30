# Integration Test Setup Instructions

## Overview
The integration test suite (`IntegrationTests.swift`) has been created but needs to be added to the Xcode project manually.

## Files Created
- ✅ `swiftwingTests/IntegrationTests.swift` - Complete integration test suite (6 scenarios)
- ✅ `TEST_COVERAGE_SUMMARY.md` - Comprehensive test documentation
- ✅ `INTEGRATION_TEST_SETUP.md` - This setup guide

## Manual Setup Steps

### 1. Add Test File to Xcode Project
1. Open `swiftwing.xcodeproj` in Xcode
2. In Project Navigator, right-click on `swiftwingTests` folder
3. Select "Add Files to swiftwingTests..."
4. Navigate to `swiftwingTests/IntegrationTests.swift`
5. Ensure "swiftwingTests" target is checked
6. Click "Add"

### 2. Configure Test Scheme (if needed)
If the scheme isn't configured for testing:

1. Click on scheme dropdown (top toolbar) → "Edit Scheme..."
2. Select "Test" action in left sidebar
3. Click "+" under "Test" section
4. Add `swiftwingTests` target
5. Ensure `IntegrationTests` is checked
6. Click "Close"

### 3. Run Tests
**Option A: Run All Integration Tests**
```bash
# Via Xcode: Cmd+U or Product → Test
# Via CLI:
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/IntegrationTests
```

**Option B: Run Specific Test**
```bash
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/IntegrationTests/testScenario1_SuccessfulScanToLibrary
```

**Option C: Run from Xcode**
1. Open `IntegrationTests.swift`
2. Click diamond icon next to test method
3. Or: Press Cmd+U to run all tests

## Test Coverage

### 6 Comprehensive Scenarios
1. ✅ **Scenario 1:** Happy path (Scan → Upload → SSE → Library)
2. ✅ **Scenario 2:** Error recovery (SSE error → Retry → Success)
3. ✅ **Scenario 3:** Offline queue (Offline → Network returns → Auto-upload)
4. ✅ **Scenario 4:** Load test (10 rapid scans < 2 minutes)
5. ✅ **Scenario 5:** Temp file cleanup verification
6. ✅ **Scenario 6:** SwiftData metadata validation

### Expected Results
- ✅ 6/6 tests pass
- ✅ Zero warnings
- ✅ Zero errors
- ✅ Duration: < 60 seconds (mocked network)

## Troubleshooting

### Issue: "No such module 'swiftwing'"
**Cause:** Test file not added to Xcode project target
**Fix:** Follow "Add Test File to Xcode Project" steps above

### Issue: "Scheme not configured for test action"
**Cause:** Test target not added to scheme
**Fix:** Follow "Configure Test Scheme" steps above

### Issue: Tests fail with "No such module 'XCTest'"
**Cause:** Test target misconfigured
**Fix:**
1. Select `swiftwingTests` target in project settings
2. Go to "Build Phases" → "Link Binary With Libraries"
3. Ensure `XCTest.framework` is present
4. If missing, click "+", search for XCTest, add it

### Issue: Simulator not booted
**Fix:**
```bash
# Boot simulator first
xcrun simctl boot "iPhone 17 Pro Max"
# Then run tests
```

## Verification

### Quick Test Run (after setup)
```bash
# Build first
xcodebuild build \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  2>&1 | xcsift

# Run tests
xcodebuild test \
  -project swiftwing.xcodeproj \
  -scheme swiftwing \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:swiftwingTests/IntegrationTests
```

### Expected Output
```
Test Suite 'IntegrationTests' started
Test Case 'testScenario1_SuccessfulScanToLibrary' passed (0.XXX seconds)
Test Case 'testScenario2_SSEErrorWithRetryAndSuccess' passed (0.XXX seconds)
Test Case 'testScenario3_OfflineQueueWithAutoUpload' passed (0.XXX seconds)
Test Case 'testScenario4_TenRapidScansCompleteWithinTwoMinutes' passed (X.XXX seconds)
Test Case 'testTempFileCleanupAfterProcessing' passed (0.XXX seconds)
Test Case 'testSwiftDataPersistsCompleteMetadata' passed (0.XXX seconds)
Test Suite 'IntegrationTests' passed
     Executed 6 tests, with 0 failures in X.XXX seconds
```

## Next Steps

1. ✅ Test file created: `swiftwingTests/IntegrationTests.swift`
2. ✅ Documentation created: `TEST_COVERAGE_SUMMARY.md`
3. ⚠️ **Manual step required:** Add `IntegrationTests.swift` to Xcode project
4. ⚠️ **Manual step required:** Run tests via Xcode (Cmd+U) or CLI
5. ✅ After tests pass: Commit with `feat: US-411 - Integration Testing (End-to-End Flow)`

## Files in This Commit

### Production Code
- No production code changes (test-only story)

### Test Code
- `swiftwingTests/IntegrationTests.swift` (NEW) - 6 integration test scenarios
- `TEST_COVERAGE_SUMMARY.md` (NEW) - Test documentation
- `INTEGRATION_TEST_SETUP.md` (NEW) - Setup instructions

### Configuration
- Requires manual Xcode project update (not included in git)

---

**Created:** January 23, 2026
**User Story:** US-411 - Integration Testing (End-to-End Flow)
**Status:** ✅ Code complete, awaiting manual Xcode setup + test run
