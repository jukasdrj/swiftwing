#!/bin/bash
# Epic 6 Sprint 2 - Quick Verification Script

echo "🔍 Epic 6 Sprint 2 - Component Verification"
echo "==========================================="
echo ""

# Check critical files exist
echo "📁 Checking file existence..."
files=(
    "swiftwing/Services/VisionTypes.swift"
    "swiftwing/Models/BookSpineInfo.swift"
    "swiftwing/Services/BookExtractionService.swift"
    "swiftwing/ConfidenceBadge.swift"
    "swiftwing/BookDetailSheetView.swift"
    "swiftwing/CameraViewModel.swift"
    "swiftwing/ReviewQueueView.swift"
    "swiftwing/Features/Settings/FeatureFlagsDebugView.swift"
)

missing_count=0
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✅ $file"
    else
        echo "  ❌ MISSING: $file"
        ((missing_count++))
    fi
done

echo ""
echo "📝 Checking key implementations..."

# Check DocumentObservation exists in VisionTypes.swift
if grep -q "struct DocumentObservation" swiftwing/Services/VisionTypes.swift 2>/dev/null; then
    echo "  ✅ DocumentObservation struct in VisionTypes.swift"
else
    echo "  ❌ DocumentObservation NOT FOUND"
    ((missing_count++))
fi

# Check BookSpineInfo has @Generable
if grep -q "@Generable" swiftwing/Models/BookSpineInfo.swift 2>/dev/null; then
    echo "  ✅ BookSpineInfo with @Generable macro"
else
    echo "  ❌ @Generable macro NOT FOUND"
    ((missing_count++))
fi

# Check .extracting state exists
if grep -q "case extracting" swiftwing/ProcessingItem.swift 2>/dev/null; then
    echo "  ✅ ProcessingState.extracting case"
else
    echo "  ❌ .extracting state NOT FOUND"
    ((missing_count++))
fi

# Check VisionService has recognizeText method
if grep -q "func recognizeText" swiftwing/Services/VisionService.swift 2>/dev/null; then
    echo "  ✅ VisionService.recognizeText() method"
else
    echo "  ❌ recognizeText() method NOT FOUND"
    ((missing_count++))
fi

# Check BookExtractionService is actor
if grep -q "actor BookExtractionService" swiftwing/Services/BookExtractionService.swift 2>/dev/null; then
    echo "  ✅ BookExtractionService actor"
else
    echo "  ❌ BookExtractionService actor NOT FOUND"
    ((missing_count++))
fi

# Check processBookOnDevice method exists
if grep -q "func processBookOnDevice" swiftwing/CameraViewModel.swift 2>/dev/null; then
    echo "  ✅ CameraViewModel.processBookOnDevice() method"
else
    echo "  ❌ processBookOnDevice() method NOT FOUND"
    ((missing_count++))
fi

# Check bookItemId bug fix (should use item.id, not UUID())
if grep -q "let bookItemId = item.id" swiftwing/CameraViewModel.swift 2>/dev/null; then
    echo "  ✅ bookItemId bug fix applied (uses item.id)"
else
    echo "  ⚠️  WARNING: bookItemId might still use UUID() - check line 299"
fi

# Check BookDetailSheetView exists
if grep -q "struct BookDetailSheetView" swiftwing/BookDetailSheetView.swift 2>/dev/null; then
    echo "  ✅ BookDetailSheetView component"
else
    echo "  ❌ BookDetailSheetView NOT FOUND"
    ((missing_count++))
fi

# Check ConfidenceBadge component
if grep -q "struct ConfidenceBadge" swiftwing/ConfidenceBadge.swift 2>/dev/null; then
    echo "  ✅ ConfidenceBadge component"
else
    echo "  ❌ ConfidenceBadge NOT FOUND"
    ((missing_count++))
fi

# Check UseOnDeviceExtraction feature flag
if grep -q "UseOnDeviceExtraction" swiftwing/Features/Settings/FeatureFlagsDebugView.swift 2>/dev/null; then
    echo "  ✅ UseOnDeviceExtraction feature flag"
else
    echo "  ❌ Feature flag NOT FOUND"
    ((missing_count++))
fi

echo ""
echo "🔨 Build verification..."
# Note: Actual build verification requires xcodebuild | xcsift
echo "  ℹ️  Run 'xcodebuild ... | xcsift' for full build verification"

echo ""
echo "=========================================="
if [[ $missing_count -eq 0 ]]; then
    echo "✅ ALL COMPONENTS VERIFIED ($missing_count issues)"
    echo ""
    echo "📋 Next steps:"
    echo "  1. Run integration tests from epic-6-sprint-2-integration-test.md"
    echo "  2. Toggle UseOnDeviceExtraction flag in app Settings"
    echo "  3. Test both pipelines (on-device vs Talaria)"
    exit 0
else
    echo "❌ VERIFICATION FAILED ($missing_count issues found)"
    echo ""
    echo "⚠️  Fix missing components before testing"
    exit 1
fi
