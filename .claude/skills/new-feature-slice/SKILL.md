---
name: new-feature-slice
description: Scaffolds a SwiftWing vertical feature slice (View, ViewModel, and Swift Testing suite). Use when the user asks for a new feature, epic slice, or /new-feature-slice.
---

Scaffold one vertical slice for SwiftWing. The app targets iOS 27 and Swift 6.4. The user provides a feature name (for example Wishlist, Export, or Settings). Create only the files below.

## Files

### `swiftwing/Features/<FeatureName>/<FeatureName>View.swift`

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

### `swiftwing/Features/<FeatureName>/<FeatureName>ViewModel.swift`

```swift
import Foundation
import Observation

@Observable
final class <FeatureName>ViewModel {
    private(set) var isLoading = false
    private(set) var error: Error?
}
```

### `swiftwingTests/Unit/Features/<FeatureName>ViewModelTests.swift`

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

- Use `@Observable`, not `ObservableObject`.
- Use Swift Testing (`@Suite`, `@Test`, `#expect`). UI tests stay on XCTest.
- Mark the view model `@MainActor` when it calls actor services.
- Log with OSLog. Do not use `print()`.
- Follow Swiss Glass in `Theme.swift`: `.ultraThinMaterial`, 12pt corners, International Orange `#FF4F00`. Do not restyle the app to stock Liquid Glass.
- Add new files to the Xcode project.
- Build with `xcodebuild` piped through `xcsift` for iPhone 18 Pro Max. Stop unless the summary is 0 errors and 0 warnings.
