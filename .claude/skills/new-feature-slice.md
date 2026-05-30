---
name: new-feature-slice
description: Scaffolds a new vertical feature slice (View + ViewModel + Service hook + Tests) following SwiftWing MVVM patterns. Usage: /new-feature-slice <FeatureName>
---

You are scaffolding a new vertical feature slice for SwiftWing iOS 26.

The user will provide a feature name (e.g. "Wishlist", "Export", "Settings"). Create the following files using the patterns below. Do not add features beyond the minimum scaffold.

## Files to create

### 1. `swiftwing/Features/<FeatureName>/<FeatureName>View.swift`
```swift
import SwiftUI

struct <FeatureName>View: View {
    @State private var viewModel = <FeatureName>ViewModel()

    var body: some View {
        Text("<FeatureName>")
    }
}

#Preview {
    <FeatureName>View()
}
```

### 2. `swiftwing/Features/<FeatureName>/<FeatureName>ViewModel.swift`
```swift
import Foundation
import Observation

@Observable
final class <FeatureName>ViewModel {
    // MARK: - State
    private(set) var isLoading = false
    private(set) var error: Error?
}
```

### 3. `swiftwingTests/Unit/Features/<FeatureName>ViewModelTests.swift`
```swift
import Testing
@testable import swiftwing

@Suite("<FeatureName>ViewModel Tests")
struct <FeatureName>ViewModelTests {
    @Test("initial state is correct")
    func initialState() {
        let vm = <FeatureName>ViewModel()
        #expect(!vm.isLoading)
        #expect(vm.error == nil)
    }
}
```

## Rules
- Use `@Observable` (not `ObservableObject`) — Swift 6.2 / iOS 26
- Use Swift Testing (`@Suite`, `@Test`, `#expect`) — not XCTest
- Use `@MainActor` on ViewModel if it calls actor services
- Use OSLog for logging — never `print()`
- Follow Swiss Glass design: `.ultraThinMaterial`, 12px corners, International Orange `#FF4F00` accent
- Add files to the Xcode project after creation (remind the user to do this if you cannot)
- Build verify after scaffolding: `xcodebuild ... | xcsift` → errors: 0, warnings: 0
