Here is the revised User Stories document for **Project Wingtip**, refocused for a native Swift/iOS architecture targeting iOS 26.1 and current-generation hardware.

The technical stack has been migrated from Flutter/Riverpod/Drift to **SwiftUI/Observation/SwiftData**, leveraging modern concurrency and native Apple frameworks.

---

# User Stories: Project Wingtip (Native iOS MVP)

## Design Language: "Swiss Utility"

* **Typography:** *JetBrains Mono* (headers/data) + *San Francisco Pro* (body - keeping system default for legibility, or *Inter* if custom font desired)
* **Palette:** `Color.black` (Background), `Color.white` (Text), `Color(red: 1.0, green: 0.23, blue: 0.19)` (Accent - "International Orange")
* **Borders:** 1px solid white borders (using `.border()` modifiers). No drop shadows.
* **Motion:** `spring(duration: 0.2)` or `.linear` for snap transitions.
* **Target:** iOS 26.1+ (Only current-gen devices).

---

## Epic 1: Foundations & Architecture

*Building the "skeleton" using modern Swift concurrency and data persistence.*

### US-101: Initialize Xcode Project with SwiftData

**As a** developer
**I want to** scaffold the app with the latest Swift stack
**So that** I have a performant, native foundation

**Acceptance Criteria:**

* [ ] Project created with Bundle ID `com.ooheynerds.wingtip`
* [ ] Minimum Deployment Target set to **iOS 26.1**
* [ ] **SwiftData** container configured for persistence (replacing Core Data/SQLite direct access)
* [ ] **Observation** framework set up for state management (replacing `ObservableObject`/Combine)
* [ ] Folder structure set: `App/`, `Features/`, `Models/`, `Services/`

**Priority:** P0 (Critical)
**Estimate:** 2 hours
**Dependencies:** None

---

### US-102: Implement "Swiss Utility" ViewModifiers

**As a** user
**I want to** experience a high-contrast, clean interface
**So that** the app feels precise and professional

**Acceptance Criteria:**

* [ ] Force `preferredColorScheme` to `.dark` (OLED optimization)
* [ ] Create custom ViewModifier `.swissBorder()` for 1px white borders
* [ ] Configure global font styles: *JetBrains Mono* for `Monospaced` text styles
* [ ] Define `Color.internationalOrange` in Asset Catalog

**Priority:** P0 (Critical)
**Estimate:** 3 hours
**Dependencies:** US-101

---

### US-103: Secure Device Identity (Keychain)

**As a** system
**I want to** retrieve a stable identifier
**So that** I can authenticate with the Talaria backend

**Acceptance Criteria:**

* [ ] Check Keychain for existing `device_id`
* [ ] If missing, generate `UUID().uuidString` and store in Keychain (prevents loss on app delete)
* [ ] Create `NetworkInterceptor` to inject `X-Device-ID` header into all `URLSession` requests
* [ ] Add "Reset Identity" button in Debug menu

**Priority:** P0 (Critical)
**Estimate:** 2 hours
**Dependencies:** US-101

---

### US-104: Offline-First Network Actor

**As a** system
**I want to** queue requests when the connection is `.unsatisfied`
**So that** I don't lose scans if the network drops

**Acceptance Criteria:**

* [ ] Implement `NWPathMonitor` within a global `NetworkActor`
* [ ] Queue outgoing scan requests if path status is `.unsatisfied`
* [ ] Show a subtle "OFFLINE" tag in the top-right corner (using `.overlay()` alignment)

**Priority:** P1 (High)
**Estimate:** 4 hours
**Dependencies:** US-103

---

## Epic 2: The Viewfinder (Capture)

*The primary interface. Leveraging AVFoundation for raw performance.*

### US-105: Zero-Lag Camera Feed

**As a** user
**I want to** see the camera immediately upon opening the app
**So that** I can capture a book spine instantly

**Acceptance Criteria:**

* [ ] `AVCaptureSession` preset set to `High` (4K/60fps supported on current gen)
* [ ] Preview layer implementation using `UIViewRepresentable` (or native SwiftUI Camera API if available in iOS 26)
* [ ] Hide Status Bar (`.statusBarHidden(true)`)
* [ ] Cold start to live feed < 0.5s

**Priority:** P0 (Critical)
**Estimate:** 4 hours
**Dependencies:** US-101, US-102

---

### US-106: Non-Blocking Shutter (Async)

**As a** user
**I want to** tap the shutter button repeatedly without waiting
**So that** I can scan a whole shelf in seconds

**Acceptance Criteria:**

* [ ] Shutter button: Circle with `.stroke(.white, lineWidth: 4)`
* [ ] On tap: Trigger `.sensoryFeedback(.impact, flexibility: .solid)`
* [ ] On tap: Flash screen white via a `ZStack` overlay opacity animation
* [ ] Capture photo asynchronously on background actor; UI remains interactive

**Priority:** P0 (Critical)
**Estimate:** 3 hours
**Dependencies:** US-105

---

### US-107: Background Image Processing (TaskGroup)

**As a** system
**I want to** compress and resize images off the main thread
**So that** the SwiftUI render loop never drops a frame

**Acceptance Criteria:**

* [ ] Use `Task.detached` with `.userInitiated` priority
* [ ] Resize `CGImage` to max 1920px long-edge
* [ ] Compress to JPEG data (0.85 quality)
* [ ] Save to `FileManager.default.temporaryDirectory`

**Priority:** P0 (Critical)
**Estimate:** 4 hours
**Dependencies:** US-106

---

### US-108: The "Processing Stack" UI

**As a** user
**I want to** see my active uploads as a queue
**So that** I know the system is working

**Acceptance Criteria:**

* [ ] Horizontal `ScrollView` above shutter button
* [ ] `LazyHStack` containing 40x60px thumbnails
* [ ] State visualization via border colors:
* Yellow: `Uploading`
* Blue: `Analyzing`
* Green: `Done`


* [ ] Use `.transition(.scale)` for entry/exit animations

**Priority:** P1 (High)
**Estimate:** 5 hours
**Dependencies:** US-107

---

### US-109: Manual Focus & Zoom

**As a** user
**I want to** pinch to zoom and tap to focus
**So that** I can capture small text on spines

**Acceptance Criteria:**

* [ ] `MagnificationGesture` binds to `AVCaptureDevice.videoZoomFactor`
* [ ] Tap gesture converts screen coordinates to device point of interest
* [ ] Draw a custom SwiftUI square bracket `[ ]` cursor at tap location

**Priority:** P1 (High)
**Estimate:** 3 hours
**Dependencies:** US-105

---

## Epic 3: The Talaria Link (Integration)

*Connecting to the backend brain using Swift Concurrency.*

### US-110: Upload Image (Multipart Request)

**As a** system
**I want to** POST the image to `/v3/jobs/scans`
**So that** I can start the analysis pipeline

**Acceptance Criteria:**

* [ ] Construct `URLRequest` with multipart/form-data boundary
* [ ] Use `URLSession.shared.upload(for:from:)`
* [ ] Decode `202 Accepted` response into struct `JobResponse { let jobId: String, let streamUrl: URL }`
* [ ] Update local job state to `.listening`

**Priority:** P0 (Critical)
**Estimate:** 4 hours
**Dependencies:** US-107, US-103

---

### US-111: AsyncSequence SSE Listener

**As a** system
**I want to** listen to Server-Sent Events for a specific Job ID
**So that** I receive real-time updates

**Acceptance Criteria:**

* [ ] Implement `URLSession.bytes(from:)` to consume the stream
* [ ] Iterate over `lines` (AsyncSequence)
* [ ] Filter for lines starting with `data:` and decode JSON
* [ ] Handle timeout (task cancellation) after 5 minutes

**Priority:** P0 (Critical)
**Estimate:** 5 hours
**Dependencies:** US-110

---

### US-112: Visualize "Progress" Events

**As a** user
**I want to** see text updates as the AI thinks
**So that** I feel the speed of the system

**Acceptance Criteria:**

* [ ] Overlay `.monospaced()` text on the specific job thumbnail
* [ ] Map status codes to user strings: "Looking...", "Reading...", "Enriching..."
* [ ] Use `withAnimation` to cross-fade text updates

**Priority:** P1 (High)
**Estimate:** 3 hours
**Dependencies:** US-111, US-108

---

### US-113: Handle "Result" Events (SwiftData Upsert)

**As a** system
**I want to** save incoming book data immediately
**So that** I can persist it to the library

**Acceptance Criteria:**

* [ ] Listen for `event: result`
* [ ] Initialize `Book` model (SwiftData macro `@Model`)
* [ ] Perform upset logic (Fetch by ISBN -> Update OR Insert new) using `ModelContext`
* [ ] Trigger `.sensoryFeedback(.success)` on completion

**Priority:** P0 (Critical)
**Estimate:** 4 hours
**Dependencies:** US-111, US-116

---

### US-114: Handle "Complete" & Cleanup

**As a** system
**I want to** clean up resources when a job finishes
**So that** I don't waste storage or battery

**Acceptance Criteria:**

* [ ] Listen for `event: complete`
* [ ] Fire-and-forget `DELETE /v3/jobs/scans/{jobId}/cleanup`
* [ ] Remove temporary JPEG from disk
* [ ] Cancel the `Task` associated with the SSE stream

**Priority:** P0 (Critical)
**Estimate:** 3 hours
**Dependencies:** US-111

---

### US-115: Handle Global Rate Limits

**As a** user
**I want to** know if I've hit the daily limit
**So that** I don't waste time snapping photos

**Acceptance Criteria:**

* [ ] Check `URLResponse` status code 429
* [ ] Extract `Retry-After` header
* [ ] Disable shutter button interaction
* [ ] Show `ContentUnavailableView` or overlay with countdown timer

**Priority:** P1 (High)
**Estimate:** 3 hours
**Dependencies:** US-110

---

## Epic 4: The Library (SwiftData)

*The permanent home for the data.*

### US-116: SwiftData Model Schema

**As a** developer
**I want to** define the `Book` model
**So that** I can store metadata efficiently

**Acceptance Criteria:**

* [ ] Create class `Book` annotated with `@Model`
* [ ] Properties: `isbn` (Attribute .unique), `title`, `author`, `coverUrl`, `format`, `addedDate`, `spineConfidence`
* [ ] Apply `@Attribute(.externalStorage)` to large data blobs if necessary (unlikely for metadata)

**Priority:** P0 (Critical)
**Estimate:** 2 hours
**Dependencies:** US-101

---

### US-117: Library Grid View

**As a** user
**I want to** see my books in a clean grid
**So that** I can browse my collection

**Acceptance Criteria:**

* [ ] `LazyVGrid` with `GridItem(.adaptive(minimum: 100))`
* [ ] Use `AsyncImage` for cover loading with a standard placeholder
* [ ] Aspect ratio 1:1.5
* [ ] If cover fails: Gray rectangle with `Text(book.title)` in `.caption` monospace

**Priority:** P0 (Critical)
**Estimate:** 5 hours
**Dependencies:** US-116, US-102

---

### US-118: Real-time List Updates (Query)

**As a** user
**I want to** see new books pop in automatically
**So that** I don't have to pull-to-refresh

**Acceptance Criteria:**

* [ ] Use `@Query(sort: \Book.addedDate, order: .reverse)` in the View
* [ ] SwiftData automatically refreshes the view upon Insert
* [ ] Apply `.animation(.default, value: books)` to the Grid

**Priority:** P1 (High)
**Estimate:** 3 hours
**Dependencies:** US-117

---

### US-119: Predicate Search

**As a** user
**I want to** search my library instantly
**So that** I can find a specific book

**Acceptance Criteria:**

* [ ] Add `.searchable(text: $searchText)` modifier to the NavigationStack
* [ ] Dynamically update `@Query` filter using `#Predicate` macro
* [ ] Filter matches against `title`, `author`, or `isbn` (case insensitive)

**Priority:** P1 (High)
**Estimate:** 4 hours
**Dependencies:** US-116, US-117

---

### US-120: "Review Needed" Indicator

**As a** user
**I want to** see which books had low confidence
**So that** I can manually check them

**Acceptance Criteria:**

* [ ] Check `spineConfidence < 0.8` (or backend flag)
* [ ] Overlay `Image(systemName: "exclamationmark.triangle.fill")` in yellow on the cover
* [ ] Add Filter Capsule: "Needs Review"

**Priority:** P2 (Medium)
**Estimate:** 3 hours
**Dependencies:** US-117, US-113

---

### US-121: Export Data (ShareLink)

**As a** user
**I want to** export my library
**So that** I own my data

**Acceptance Criteria:**

* [ ] Create a CSV string generator struct
* [ ] Use SwiftUI `ShareLink` pointing to the generated CSV data
* [ ] Filename: `wingtip_library_[date].csv`

**Priority:** P2 (Medium)
**Estimate:** 3 hours
**Dependencies:** US-116

---

## Epic 5: Detail & Interaction

*The "Swiss Utility" feel comes from these interaction details.*

### US-122: Minimal Book Detail Sheet

**As a** user
**I want to** tap a book to see its data
**So that** I can verify the scan

**Acceptance Criteria:**

* [ ] Use `.sheet(item: $selectedBook)`
* [ ] Set `presentationDetents([.medium, .large])`
* [ ] Layout: `HStack` { Cover; Vstack { Metadata } }
* [ ] Fields using `TextField` for quick inline editing

**Priority:** P1 (High)
**Estimate:** 5 hours
**Dependencies:** US-117, US-102

---

### US-123: The "Raw Data" Toggle

**As a** user
**I want to** see the raw JSON for a book
**So that** I can geek out on the metadata

**Acceptance Criteria:**

* [ ] `Toggle("Raw JSON", isOn: $showJson)`
* [ ] Conditional View: `Text(jsonString).font(.custom("JetBrainsMono", size: 10))`
* [ ] Syntax highlighting logic (Green text)

**Priority:** P3 (Low)
**Estimate:** 2 hours
**Dependencies:** US-122

---

### US-124: Context Menu Delete

**As a** user
**I want to** remove bad scans easily
**So that** my library stays clean

**Acceptance Criteria:**

* [ ] Add `.contextMenu` to grid items
* [ ] Action: `Button("Delete", role: .destructive)`
* [ ] `modelContext.delete(book)` inside the action closure

**Priority:** P2 (Medium)
**Estimate:** 4 hours
**Dependencies:** US-117

---

### US-125: Sensory Feedback Strategy

**As a** user
**I want to** feel the app working
**So that** I don't have to look at the screen constantly

**Acceptance Criteria:**

* [ ] Shutter: `.sensoryFeedback(.impact)`
* [ ] Scan Success: `.sensoryFeedback(.success)`
* [ ] Error: `.sensoryFeedback(.error)`
* [ ] Use `.sensoryFeedback(trigger: stateVariable)` modifier

**Priority:** P1 (High)
**Estimate:** 2 hours
**Dependencies:** US-106, US-113

---

### US-126: Cache Management

**As a** user
**I want to** clear cached cover images
**So that** the app doesn't eat up my storage

**Acceptance Criteria:**

* [ ] Settings Button: "Clear Image Cache"
* [ ] Execute `URLCache.shared.removeAllCachedResponses()`
* [ ] Calculate disk usage of `fsCachedData` directory for display

**Priority:** P2 (Medium)
**Estimate:** 3 hours
**Dependencies:** US-117

---

## Epic 6: Polish & Launch

*Getting ready for the store.*

### US-127: App Icon & Launch Screen

**As a** user
**I want to** recognize the app on my home screen
**So that** I can launch it quickly

**Acceptance Criteria:**

* [ ] Add App Icon set (Solid Black background, White glyph)
* [ ] Configure `LaunchScreen.storyboard` (or plist equivalent in iOS 26) with background color `#000000`
* [ ] Ensure dark mode compatibility is seamless

**Priority:** P2 (Medium)
**Estimate:** 3 hours
**Dependencies:** US-102

---

### US-128: Permission Priming

**As a** user
**I want to** understand why you need camera access
**So that** I trust the app

**Acceptance Criteria:**

* [ ] Check `AVCaptureDevice.authorizationStatus` on launch
* [ ] If `.notDetermined`, show full screen "Primer" View
* [ ] "Continue" button calls `AVCaptureDevice.requestAccess`

**Priority:** P1 (High)
**Estimate:** 3 hours
**Dependencies:** US-105

---

### US-129: Content Unavailable (Empty State)

**As a** user
**I want to** see helpful text when my library is empty
**So that** I know what to do

**Acceptance Criteria:**

* [ ] Use native `ContentUnavailableView`
* [ ] Label: "No Books Scanned"
* [ ] Description: "Tap the [O] button to capture your first spine."
* [ ] System Image: `books.vertical`

**Priority:** P2 (Medium)
**Estimate:** 2 hours
**Dependencies:** US-117

---

### US-130: Error Overlay

**As a** user
**I want to** see errors without them blocking me
**So that** I can keep scanning

**Acceptance Criteria:**

* [ ] Create a global overlay View Modifier listening to an `ErrorManager` environment object
* [ ] Animation: Slide up from bottom
* [ ] Style: Black capsule, white text, red border
* [ ] Auto-dismiss after 3 seconds

**Priority:** P1 (High)
**Estimate:** 2 hours
**Dependencies:** US-102

---

## Summary Statistics

**Total User Stories:** 30
**Total Estimated Hours:** ~98 hours

### Priority Breakdown

* **P0 (Critical):** 13 stories
* **P1 (High):** 11 stories
* **P2 (Medium):** 5 stories
* **P3 (Low):** 1 story

### Critical Path (MVP)

1. **US-101 → US-116:** Project Setup & SwiftData (4 hours)
2. **US-105 → US-106 → US-107:** AVFoundation Camera & Processing (11 hours)
3. **US-110 → US-111 → US-113:** Networking & Data Ingestion (13 hours)
4. **US-117:** Library Grid (5 hours)

**MVP Total: ~33 hours**