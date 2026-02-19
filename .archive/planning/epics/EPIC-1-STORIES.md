# Epic 1: Foundation & Walking Skeleton

**Goal:** Build the minimal end-to-end skeleton connecting UI → Logic → Data → Network. Proves the architecture works without over-engineering.

**Philosophy:** "Walking Skeleton" approach - connect all layers with minimal functionality. Defer complexity (offline-first, full design system) to later epics. Focus on dopamine-generating visible progress.

**Duration:** ~1 week (solo dev, part-time)
**Stories:** 5 stories, ~8.5 hours estimated

---

## 🎯 Epic Goals

### Primary Goal
Prove the architecture works end-to-end (UI → SwiftData → Network) with minimal code.

### Secondary Goal
Generate visible progress quickly to maintain momentum.

### Anti-Goals (What NOT to Build)
- ❌ Don't build a full design system (defer to Epic 2)
- ❌ Don't implement offline-first networking (defer to Epic 4)
- ❌ Don't build the camera capture yet (defer to Epic 2)
- ❌ Don't build the library grid UI (defer to Epic 3)
- ❌ Don't integrate Talaria API (defer to Epic 4)

---

## 📋 User Stories

### US-101: Initialize Xcode Project with SwiftData

**Priority:** P1 (Critical)
**Estimate:** 1 hour
**Dependencies:** None

**As a** developer
**I want to** scaffold a clean iOS 26 project with SwiftData
**So that** I have a proven compilation target and modern persistence layer

#### Acceptance Criteria

- [ ] Create new Xcode project with bundle ID `com.ooheynerds.swiftwing`
- [ ] Set minimum deployment target to **iOS 26.0**
- [ ] Configure SwiftData ModelContainer in App entry point
- [ ] Create empty `Models/` folder with placeholder `Book.swift` file
- [ ] Run project on simulator - app launches to blank white screen
- [ ] Zero compiler warnings or errors
- [ ] SwiftLint and SwiftFormat configured (optional but recommended)

#### Technical Notes

- Use `@main` App struct with `WindowGroup`
- ModelContainer should use `.inMemory` for now (file persistence in Epic 3)
- Folder structure: `App/`, `Features/`, `Models/`, `Services/`
- Defer code signing and provisioning until ready to test on device

#### Notes

Keep it simple. Don't over-configure. Goal is a working build target.

---

### US-102: Minimal Theme Constants (Not Full Design System)

**Priority:** P2 (High)
**Estimate:** 2 hours
**Dependencies:** US-101

**As a** developer
**I want to** basic color and font constants defined
**So that** I can build UI without hard-coding values, but I don't need a full design system yet

#### Acceptance Criteria

- [ ] Create `Theme.swift` file with Color extensions (`swissBackground`, `swissText`, `internationalOrange`)
- [ ] Add custom font **JetBrains Mono** to project (1 weight only - Regular)
- [ ] Create simple ViewModifier for `.swissGlassCard()` - black background + thin material
- [ ] Force app to dark mode via `preferredColorScheme(.dark)`
- [ ] Build a `HelloWorldView` using these constants to verify they work
- [ ] No need for full component library or Figma designs yet

#### Technical Notes

**Swiss Glass Hybrid Design:**
- Typography: JetBrains Mono for data, SF Pro (system) for UI
- Black base + `.ultraThinMaterial` overlays
- Defer animations, haptics, and complex modifiers until Epic 2

**Example ViewModifier:**
```swift
extension View {
    func swissGlassCard() -> some View {
        self
            .background(.black)
            .overlay(Material.ultraThin.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

#### Notes

Resist urge to build a full design system. You'll iterate on this in Epic 2 when you build real UI.

---

### US-103: Basic SwiftData Book Model (Dummy Data)

**Priority:** P3 (High)
**Estimate:** 1.5 hours
**Dependencies:** US-101, US-102

**As a** developer
**I want to** create a minimal Book @Model and save one dummy record
**So that** I prove SwiftData persistence works

#### Acceptance Criteria

- [ ] Define `Book` class with `@Model` macro in `Models/Book.swift`
- [ ] Properties: `id` (UUID), `title` (String), `author` (String), `isbn` (String, `@Attribute(.unique)`)
- [ ] Defer optional fields (`coverUrl`, `format`, `confidence`) until Epic 3
- [ ] Create `LibraryView` with `@Query` to fetch all books
- [ ] Add a Button that inserts a dummy book: `Book(title: "Test Book", author: "Test Author", isbn: "1234567890")`
- [ ] Display count of books in a Text view: `"Books: \(books.count)"`
- [ ] Verify tapping button increments count (proves save works)

#### Technical Notes

```swift
@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    @Attribute(.unique) var isbn: String

    init(title: String, author: String, isbn: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.isbn = isbn
    }
}
```

- Use `@Query(sort: \Book.title)` in LibraryView
- ModelContext is automatically injected via `@Environment`
- Keep UI minimal - just a VStack with Text + Button
- ISBN uniqueness will be important later but don't handle duplicates yet

#### Notes

Don't build the full library grid yet. Just prove you can save and query. Grid comes in Epic 3.

---

### US-104: Basic Network Fetch (Prove Connectivity)

**Priority:** P4 (High)
**Estimate:** 1.5 hours
**Dependencies:** US-101

**As a** developer
**I want to** fetch one JSON object from a test endpoint
**So that** I prove URLSession async/await works before building the complex Talaria integration

#### Acceptance Criteria

- [ ] Create `NetworkService.swift` with one async function: `fetchTestData()`
- [ ] Use `URLSession.shared.data(from:)` to fetch from `https://jsonplaceholder.typicode.com/posts/1`
- [ ] Decode JSON into a simple struct `TestPost { let id: Int; let title: String }`
- [ ] Add a Button in ContentView that calls `fetchTestData()` in a Task
- [ ] Display fetched title in a Text view
- [ ] Handle errors with basic try/catch and print to console
- [ ] **NO** offline queue, **NO** retry logic, **NO** actor isolation yet (Epic 4)

#### Technical Notes

```swift
struct TestPost: Codable {
    let id: Int
    let title: String
}

class NetworkService {
    func fetchTestData() async throws -> TestPost {
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TestPost.self, from: data)
    }
}
```

- Use async/await, not Combine or callbacks
- Don't create NetworkActor yet - just a simple class with async funcs
- Don't add device ID header yet (Epic 4)
- Don't handle rate limits or offline mode (Epic 4)
- JSONDecoder can be basic - no custom date formatters needed

#### Notes

Defer all complexity. This is a smoke test for networking. Talaria integration comes in Epic 4.

---

### US-105: Camera Permission Primer Screen

**Priority:** P5 (High)
**Estimate:** 2 hours
**Dependencies:** US-102

**As a** user
**I want to** see a primer screen explaining why camera access is needed
**So that** I trust the app before granting permission

#### Acceptance Criteria

- [ ] Create `CameraPermissionPrimerView` with black background
- [ ] Display title: "SwiftWing Needs Camera Access"
- [ ] Display body text: "We use your camera to scan book spines. Images are processed and deleted immediately."
- [ ] Add "Continue" button with international orange accent
- [ ] On tap, request camera permission using `AVCaptureDevice.requestAccess(for: .video)`
- [ ] Navigate to ContentView after permission granted
- [ ] Handle denied case: Show alert with instructions to enable in Settings
- [ ] Check permission status on app launch - skip primer if already granted

#### Technical Notes

```swift
// Check permission status
let status = AVCaptureDevice.authorizationStatus(for: .video)

switch status {
case .authorized:
    // Skip primer, go to main view
case .denied, .restricted:
    // Show settings alert
case .notDetermined:
    // Show primer
}

// Request permission
AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async {
        // Handle result
    }
}
```

- Use `@State` for permission status tracking
- Store primer shown status in UserDefaults (don't show every time)
- Add `NSCameraUsageDescription` to Info.plist:
  - "SwiftWing uses your camera to scan book spines for automatic identification."
- Defer actual camera preview to Epic 2 - this story is just the primer

#### Notes

This is important for App Store approval. Don't skip permissions UX.

---

## ✅ Definition of Done (Epic 1)

### Code Quality
- ✅ All acceptance criteria met
- ✅ Zero compiler warnings
- ✅ Code follows Swift 6.2 strict concurrency (actor isolation where needed)
- ✅ All new code has inline comments explaining non-obvious logic

### Testing
- ✅ App launches successfully on iOS 26 simulator
- ✅ Manual verification: Can tap button to insert dummy book and see count increment
- ✅ Manual verification: Can tap button to fetch test JSON and see title display
- ✅ Manual verification: Camera primer shows on first launch, skips on subsequent launches

### Documentation
- ✅ Update README with setup instructions (Xcode version, Swift version, dependencies)
- ✅ Document JetBrains Mono font installation in README

---

## 🎬 Epic 1 Demo

**At the end of Epic 1, you should be able to:**

1. Launch app
2. See camera permission primer
3. Grant camera permission
4. Tap button to insert dummy book and see count increment
5. Tap button to fetch test JSON and see title display

**If it doesn't work, Epic 1 is not complete.**

---

## ⏱️ Momentum Check

Epic 1 should take **~1 week** for a solo dev working evenings/weekends.

**If it takes longer, you're over-engineering.** Cut scope, defer complexity, ship the skeleton.

---

## 🔮 Next Epic Preview

### Epic 2: The Viewfinder
Build actual camera preview, shutter button, and image capture. Focus on making the core scanner experience feel good.

**Key Stories:**
- Zero-lag camera preview
- Non-blocking shutter button
- Image capture and save to temp directory
- Processing queue UI (thumbnails with state colors)

### Epic 3: The Library
Build the book grid UI, search, and full SwiftData schema with cover images.

**Key Stories:**
- Library grid with LazyVGrid
- Real-time updates with @Query
- Full-text search
- Cover image loading with AsyncImage

### Epic 4: Talaria Integration
Replace test endpoint with real Talaria API, SSE streaming, and offline queue.

**Key Stories:**
- Multipart image upload to Talaria
- Server-Sent Events listener
- Real-time progress updates
- Result handling and SwiftData upsert
- Offline queue with retry logic

---

## 📊 Epic 1 Summary

| Metric | Value |
|--------|-------|
| Total Stories | 5 |
| Total Estimate | ~8.5 hours |
| Priority Breakdown | All P1-P5 (High) |
| Dependencies | Linear (US-101 → US-102 → US-103/104/105) |
| Epic Duration | 1 week (part-time) |

**Remember:** The goal is **momentum**, not perfection. Ship the skeleton, then iterate.

---

**Created:** 2026-01-22
**Epic:** 1 of 6
**Status:** Ready to implement
**Ralph-TUI:** Use epic-1.json for task orchestration
