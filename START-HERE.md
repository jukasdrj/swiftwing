# 🚀 SwiftWing - Start Here

**Welcome to SwiftWing!** This is your native iOS 26 book spine scanner app.

---

## 📋 Quick Start

### 1. Read the Planning Docs (5 minutes)

| File | Purpose | Read First? |
|------|---------|-------------|
| **START-HERE.md** | This file - orientation | ✅ **Yes** |
| **EPIC-1-STORIES.md** | Your implementation guide | ✅ **Yes** |
| **PRD.md** | Full product requirements | Optional |
| **findings.md** | iOS 26 technical research | Optional |

### 2. Load Epic 1 into Ralph-TUI

```bash
# Load the JSON into ralph-tui
ralph-tui load epic-1.json
```

### 3. Start Building

Begin with **US-101** (Xcode project setup) and work through Epic 1 in order.

---

## 🎯 What You're Building

**SwiftWing** scans book spines with your camera and uses AI to automatically identify and catalog books.

**Core Flow:**
1. User opens app → Camera viewfinder (full screen)
2. Tap shutter → Capture book spine image
3. Upload to Talaria AI backend → Real-time SSE stream
4. Results appear in library grid → Full metadata with cover art

**Tech Stack:**
- SwiftUI + SwiftData (native iOS 26)
- Swift 6.2 Concurrency (actors, async/await)
- AVFoundation (camera)
- Server-Sent Events (real-time updates)

---

## 🏗️ Epic 1: Walking Skeleton (This Week)

**Goal:** Connect all layers (UI → Data → Network) with minimal code.

**Stories:**
1. **US-101:** Xcode project + SwiftData setup (1 hr)
2. **US-102:** Minimal theme constants (2 hrs)
3. **US-103:** Basic Book model + dummy data (1.5 hrs)
4. **US-104:** Test network fetch (1.5 hrs)
5. **US-105:** Camera permission primer (2 hrs)

**Total:** ~8 hours (1 week part-time)

**Demo at the end:** Launch app → Grant camera permission → Tap to insert dummy book (see count) → Tap to fetch test JSON (see title).

---

## 🎨 Design Language: Swiss Glass Hybrid

**60% Swiss Utility / 40% Liquid Glass**

### Colors
```swift
.background(.black)                    // Swiss - OLED black base
.foreground(.white)                    // Swiss - white text
.accentColor(Color.internationalOrange) // Swiss - #FF3B30
.background(.ultraThinMaterial)        // Glass - translucent overlays
```

### Typography
- **Data/IDs:** JetBrains Mono (brand identity)
- **UI Labels:** San Francisco Pro (native)

### Components
```swift
// Example: Swiss Glass card
.background(.black)
.overlay(.ultraThinMaterial.opacity(0.3))
.clipShape(RoundedRectangle(cornerRadius: 12))
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(.white, lineWidth: 2)
)
```

---

## 📚 Key Principles (Solo Dev)

### 1. Walking Skeleton First
Connect all layers with minimal functionality. Defer complexity.

**Good:**
- ✅ Dummy data that proves SwiftData works
- ✅ Test endpoint that proves networking works
- ✅ Basic theme constants (not full design system)

**Bad:**
- ❌ Full offline-first network layer in Epic 1
- ❌ Complete design system with animations
- ❌ Perfect camera capture before proving basics

### 2. Small Stories = Quick Wins
Each story should take 1-2 hours max. Ship fast, iterate.

### 3. Visible Progress = Momentum
Prioritize features that put pixels on screen.

### 4. Defer Complexity
- **Epic 1:** Prove it works (skeleton)
- **Epic 2:** Make it functional (camera)
- **Epic 3:** Make it beautiful (library UI)
- **Epic 4:** Make it robust (Talaria integration, offline mode)

---

## 🔧 Setup Instructions

### Prerequisites

- **Xcode:** 16.0+ (for iOS 26 SDK)
- **macOS:** Sonoma 14.0+
- **Swift:** 6.2
- **Device/Simulator:** iOS 26.0+

### Dependencies

**Zero external dependencies!** SwiftWing uses only native Apple frameworks:
- SwiftUI (UI)
- SwiftData (persistence)
- AVFoundation (camera)
- Foundation (networking)

### Font Installation

1. Download **JetBrains Mono** Regular: https://www.jetbrains.com/lp/mono/
2. Add `JetBrainsMono-Regular.ttf` to Xcode project
3. Add to `Info.plist`:
   ```xml
   <key>UIAppFonts</key>
   <array>
       <string>JetBrainsMono-Regular.ttf</string>
   </array>
   ```

### Camera Permission

Add to `Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>SwiftWing uses your camera to scan book spines for automatic identification.</string>
```

---

## 📖 Documentation Map

### Planning Docs (Already Done)
- **PRD.md** - Full product requirements (700 lines)
- **findings.md** - iOS 26 APIs & architecture research (350 lines)
- **DESIGN-DECISION.md** - Why Swiss Glass Hybrid (400 lines)
- **task_plan.md** - Development roadmap (200 lines)

### Implementation Guides
- **EPIC-1-STORIES.md** - Human-readable Epic 1 stories (400 lines)
- **epic-1.json** - Ralph-TUI configuration (180 lines)

### Original Reference
- **US-swift.md** - Original 30 user stories (will be revised per epic)

---

## 🎯 Success Metrics

| Metric | Target | When |
|--------|--------|------|
| Epic 1 Complete | 5/5 stories done | End of Week 1 |
| Camera Launch | < 0.5s cold start | Epic 2 |
| Scan Success Rate | > 95% | Epic 4 |
| UI Frame Rate | > 55 FPS | Epic 2-3 |

---

## ⚠️ Anti-Patterns (Don't Do This)

### ❌ Over-Engineering
```swift
// BAD: Full dependency injection framework in Epic 1
class NetworkServiceFactory {
    func makeService(config: NetworkConfig) -> NetworkServiceProtocol { ... }
}

// GOOD: Simple class that works
class NetworkService {
    func fetch() async throws -> Data { ... }
}
```

### ❌ Premature Abstraction
```swift
// BAD: Generic repository pattern before you know what you need
protocol Repository<T> {
    func fetch() async throws -> [T]
    func save(_ item: T) async throws
}

// GOOD: Concrete implementation that solves your problem
class BookStore {
    func saveBook(_ book: Book) { ... }
}
```

### ❌ Analysis Paralysis
Don't spend 3 days designing the perfect architecture. Build the skeleton, ship it, iterate.

---

## 🚀 Getting Started Checklist

- [ ] Read this file (START-HERE.md)
- [ ] Read EPIC-1-STORIES.md
- [ ] Load epic-1.json into ralph-tui
- [ ] Install JetBrains Mono font
- [ ] Create new Xcode project (US-101)
- [ ] Set deployment target to iOS 26.0
- [ ] Configure SwiftData ModelContainer
- [ ] Ship US-101 in < 1 hour
- [ ] Move to US-102

---

## 🤝 Need Help?

### Debugging SwiftData
```swift
// Enable SwiftData debug logging
let container = ModelContainer(
    for: Book.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)
// Check Xcode console for SQL logs
```

### Camera Not Working
1. Check Info.plist has `NSCameraUsageDescription`
2. Check permission status: `AVCaptureDevice.authorizationStatus(for: .video)`
3. Run on real device (simulator camera is limited)

### Build Errors
1. Clean build folder: Cmd+Shift+K
2. Delete derived data: `~/Library/Developer/Xcode/DerivedData`
3. Restart Xcode

---

## 📊 Epic Roadmap

| Epic | Focus | Duration | Status |
|------|-------|----------|--------|
| **1** | **Foundation (Skeleton)** | **1 week** | **→ Start Here** |
| 2 | Viewfinder (Camera) | 1-2 weeks | Pending |
| 3 | Library (UI + SwiftData) | 1-2 weeks | Pending |
| 4 | Talaria Integration (API + SSE) | 1-2 weeks | Pending |
| 5 | Polish (Details + Interaction) | 1 week | Pending |
| 6 | Launch (App Store Prep) | 1 week | Pending |

**Total:** 8-10 weeks to MVP

---

## 🎉 You're Ready!

Epic 1 is designed to be **achievable in 1 week** working part-time. If you finish faster, great! If it takes longer, you're probably over-engineering.

**Remember:** The goal is **momentum**, not perfection.

**Now go build something!** 🚀

---

**Created:** 2026-01-22
**Project:** SwiftWing
**Epic:** 1 of 6
**Status:** Ready to implement
