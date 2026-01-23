# SwiftWing Epic Roadmap

**All 6 Epics at a Glance**

---

## 📅 Timeline Overview

| Epic | Feature | Duration | Status |
|------|---------|----------|--------|
| **1** | Foundation (Skeleton) | 1 week | ✅ Complete |
| **2** | Viewfinder (Camera) | 1-2 weeks | 🟢 Ready to Start |
| **3** | Library (Browse/Search) | 1-2 weeks | ⚪ Pending |
| **4** | Talaria Integration (AI) | 1-2 weeks | ⚪ Pending |
| **5** | Polish (UX Details) | 1 week | ⚪ Pending |
| **6** | Launch (App Store) | 1 week | ⚪ Pending |

**Total:** 8-10 weeks to MVP

---

## Epic 1: Foundation & Walking Skeleton ✅

**Type:** Horizontal (exception - skeleton required)
**Duration:** 1 week
**Stories:** 5 (~8.5 hours)

### What You're Building
Minimal end-to-end connection: UI → Data → Network

### User Stories
- US-101: Xcode project + SwiftData
- US-102: Minimal theme constants
- US-103: Basic Book model + dummy data
- US-104: Test network fetch
- US-105: Camera permission primer

### Demo
Launch app → Grant permission → Insert dummy book → Fetch test JSON

### Files
- ✅ `epic-1.json` (ralph-tui config)
- ✅ `EPIC-1-STORIES.md` (implementation guide)

---

## Epic 2: The Viewfinder (Camera Experience) 📷

**Type:** Vertical Slice - Camera Feature
**Duration:** 1-2 weeks
**Stories:** 6 (~21 hours)

### What You're Building
Complete camera scanning experience (no AI results yet)

### User Stories
- US-201: Zero-lag camera preview (< 0.5s cold start)
- US-202: Non-blocking shutter (rapid fire)
- US-203: Background image processing (async)
- US-204: Processing queue UI (live thumbnails)
- US-205: Manual focus & zoom (pinch/tap)
- US-206: Swiss Glass design system formalization

### Demo
Open app → Instant camera → Tap 10 times fast → See 10 thumbnails processing → Watch them complete

### User Value
**Can actually scan books!** (Just can't get AI results yet)

### Deferred to Epic 4
- Upload to Talaria
- SSE streaming
- AI recognition

### Files
- ✅ `epic-2.json` (ralph-tui config)

---

## Epic 3: The Library (Browse & Search) 📚

**Type:** Vertical Slice - Display Feature
**Duration:** 1-2 weeks
**Stories:** 6-7 (~18 hours estimated)

### What You're Building
Complete library browsing and management

### Planned User Stories
- US-301: Full SwiftData Book schema (add all fields)
- US-302: Library grid with LazyVGrid (3 columns)
- US-303: Real-time list updates (@Query reactive)
- US-304: Full-text search with predicates
- US-305: Book detail sheet (edit metadata)
- US-306: Context menu delete (swipe to remove)
- US-307: Empty states (when library is empty)

### Demo
View library → See 50 books in grid → Search "tolkien" → Tap book → Edit title → Delete book

### User Value
**Can browse and manage collection!** (Even if books are manually added)

### Connects to Epic 2
Replace dummy books with real scans from camera

---

## Epic 4: Talaria Integration (AI Magic) 🤖

**Type:** Vertical Slice - AI Enrichment Feature
**Duration:** 1-2 weeks
**Stories:** 6-7 (~20 hours estimated)

### What You're Building
Full AI-powered book recognition via Talaria backend

### Planned User Stories
- US-401: Multipart image upload to Talaria
- US-402: Server-Sent Events (SSE) listener
- US-403: Progress event visualization
- US-404: Result event handling (SwiftData upsert)
- US-405: Complete event + cleanup
- US-406: Rate limit handling (429 responses)
- US-407: Offline queue with retry logic

### Demo
Scan book → Upload to Talaria → See "Reading..." → Book appears in library with full metadata + cover

### User Value
**Books automatically identified!** This is the "magic" moment.

### Enhances Epic 2
Camera scans now produce AI-enriched results (not just JPEG files)

### Architecture Decision: Vision Framework vs Talaria

**Epic 4 will evaluate THREE architecture options:**

**Option A: Talaria-Only (Original Plan)**
- Upload full images to Talaria backend
- SSE streaming for real-time results
- Backend handles all AI/OCR/enrichment

**Option B: Hybrid Vision + Talaria (iOS 26 Native)**
- On-device Vision framework OCR extracts text from spine
- Send text (not images) to Talaria for parsing/enrichment
- **Benefits:** Privacy (no image upload), faster (less data), works with poor connectivity
- **Tradeoffs:** More complex integration

**Option C: Vision Fallback**
- Primary: Talaria (best accuracy)
- Fallback: Vision OCR (offline mode)
- Best of both worlds, highest complexity

**Decision Point:** Test both Vision and Talaria approaches with real book spines during Epic 4 development. Measure accuracy, speed, privacy, and offline capabilities before choosing architecture.

**See:** [findings.md - iOS 26 Vision Framework](findings.md) for technical details on VNRecognizeTextRequest and Core ML 4.0 capabilities

---

## Epic 5: Polish & Interaction Details ✨

**Type:** Vertical Slice - UX Feature
**Duration:** 1 week
**Stories:** 5-6 (~15 hours estimated)

### What You're Building
Production-quality polish and edge cases

### Planned User Stories
- US-501: Haptic feedback strategy (all interactions)
- US-502: Review-needed indicator (low confidence)
- US-503: Cache management (clear images)
- US-504: Error overlay system (non-blocking)
- US-505: Raw JSON toggle (developer mode)
- US-506: CSV export (data ownership)

### Demo
All interactions have haptics → Errors show gracefully → Can export library to CSV

### User Value
**App feels professional and polished!** Ready to show friends.

---

## Epic 6: Launch & App Store Prep 🚀

**Type:** Vertical Slice - Distribution Feature
**Duration:** 1 week
**Stories:** 4-5 (~12 hours estimated)

### What You're Building
App Store submission requirements

### Planned User Stories
- US-601: App icon + launch screen
- US-602: Onboarding flow (3 slides)
- US-603: Privacy policy + terms
- US-604: App Store screenshots + metadata
- US-605: TestFlight beta (friends & family)

### Demo
Install from TestFlight → Smooth onboarding → Works perfectly

### User Value
**App is publicly available!** Users can download and use.

---

## 🎯 Vertical Slice Strategy

### How Each Epic Connects

```
Epic 1 (Skeleton)
    ↓
Epic 2 (Camera) → Saves JPEGs to temp files
    ↓
Epic 3 (Library) → Displays saved books (from Epic 2 or manual)
    ↓
Epic 4 (AI) → Enriches Epic 2 scans + updates Epic 3 library
    ↓
Epic 5 (Polish) → Enhances Epic 2-4 UX
    ↓
Epic 6 (Launch) → Ships Epic 1-5 to users
```

**Key Point:** Each epic is SHIPPABLE. If you stop after Epic 3, you have a working camera + library app (just no AI).

---

## 🛠️ What Each Epic Delivers

| After Epic | You Have... | Can Demo... |
|-----------|-------------|-------------|
| **1** | Compiling app | "It launches and saves data" |
| **2** | Working scanner | "I can scan 10 books in 30 seconds" |
| **3** | Browsable library | "I have 100 books in a searchable grid" |
| **4** | AI recognition | "Scanned spine → got full metadata" |
| **5** | Polished UX | "Feels like a real app" |
| **6** | App Store build | "Download it on TestFlight" |

---

## 📊 Effort Distribution

```
Epic 1: ████░░░░░░ 10% (foundation)
Epic 2: ████████░░ 25% (camera is complex)
Epic 3: ██████░░░░ 20% (UI grids + SwiftData)
Epic 4: ████████░░ 25% (networking + SSE)
Epic 5: ████░░░░░░ 15% (polish)
Epic 6: ███░░░░░░░ 5%  (admin tasks)
```

**Camera and AI integration are the hardest parts.**

---

## 🔄 Flexibility & Scope Changes

### Can Skip
- ✅ Epic 5 (Polish) - App works without it
- ✅ Epic 6 (Launch) - Can use for personal use only
- ✅ US-205 in Epic 2 (Zoom/focus) - Nice to have
- ✅ US-306 in Epic 3 (Delete) - Can delete from detail sheet

### Can't Skip
- ❌ Epic 1 (Foundation) - Nothing works without it
- ❌ Epic 2 (Camera) - Core feature
- ❌ Epic 4 (AI) - Core value prop

### Minimum Viable Product (MVP)
**Epic 1 + Epic 2 + Epic 3 + Epic 4 = Working AI book scanner**

Everything else is polish.

---

## 🎮 Solo Dev Strategy

### Week-by-Week
- **Week 1:** Epic 1 (foundation)
- **Week 2-3:** Epic 2 (camera)
- **Week 4-5:** Epic 3 (library)
- **Week 6-7:** Epic 4 (AI)
- **Week 8:** Epic 5 (polish)
- **Week 9:** Epic 6 (launch)
- **Week 10:** Buffer (testing, bug fixes)

### If Behind Schedule
1. Cut Epic 5 (launch with good-enough UX)
2. Cut US-205/206 from Epic 2 (skip zoom/focus)
3. Cut US-307 from Epic 3 (skip empty states)
4. Cut US-407 from Epic 4 (skip offline queue)

**Core MVP: Epic 1-4 only = 6-8 weeks**

---

## 📈 Progress Tracking

### After Each Epic, Ask:
1. ✅ Can I demo this feature to someone?
2. ✅ Does it solve a user problem?
3. ✅ Would I use this myself?

If "yes" to all three → Epic successful!

---

## 🔮 Future Epics (Post-Launch)

After Epic 6, you could add:

- **Epic 7:** Social features (share library, friend recommendations)
- **Epic 8:** Collections (organize books into shelves)
- **Epic 9:** Reading progress (track what you've read)
- **Epic 10:** Loan tracking (who borrowed what)
- **Epic 11:** iPad version (optimized layout)
- **Epic 12:** Widgets (home screen library stats)

**But don't plan these now!** Ship the MVP first.

---

## 🎯 Success Criteria

### Epic 1
✅ App launches, saves data, fetches JSON

### Epic 2
✅ Can rapid-fire scan 10 books in 30 seconds with no UI lag

### Epic 3
✅ Can search through 100+ books instantly

### Epic 4
✅ Scanned book spine → Full metadata in < 5 seconds

### Epic 5
✅ App feels as good as Apple's stock apps

### Epic 6
✅ Friends can download and use successfully

---

**Current Status:** ✅ Epic 1 COMPLETE (All 5 stories done, build successful)
**Next Up:** Epic 2 (camera) - the fun part! 📷

**Epic 1 Completion Date:** January 22, 2026
**Epic 1 Grade:** A (95/100) - Excellent foundation

**Remember:** Each epic is a complete feature. Ship working code every 1-2 weeks.
