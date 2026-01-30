# Feature-Based Vertical Slices: Project Management Strategy

**For Solo Developers Building SwiftWing**

---

## 🍰 What is a Vertical Slice?

A **vertical slice** delivers one **complete user feature** across all architectural layers:

```
┌─────────────────────────────────────┐
│         Feature: "Scan Book"         │
├─────────────────────────────────────┤
│  UI Layer        CameraView          │
│  Logic Layer     ImageProcessor      │
│  Data Layer      TempFileStorage     │
│  Network Layer   (deferred)          │
└─────────────────────────────────────┘
           ↓
    WORKING FEATURE!
```

Compare to **horizontal slicing** (layers):

```
Epic 1: Build all Models      ← No working feature
Epic 2: Build all Services     ← Still no working feature
Epic 3: Build all Views        ← Still no working feature
Epic 4: Connect everything     ← First working feature (finally!)
```

---

## 🎯 Why Vertical Slices Work for Solo Devs

### 1. **Instant User Value**
Each epic delivers a **working feature** users can interact with.

**Vertical:** After Epic 2, users can scan books (even without AI results)
**Horizontal:** After Epic 2, you just have "all the services" (nothing to demo)

### 2. **Continuous Motivation**
You see **visible progress** every week.

**Vertical:** "Look, I can scan and see thumbnails!"
**Horizontal:** "I built 5 service classes... they don't do anything yet."

### 3. **Early Feedback**
Ship features incrementally, learn what works.

**Vertical:** Test camera UX in week 2, iterate in week 3
**Horizontal:** Don't see camera until week 6, too late to change

### 4. **Flexible Scope**
Easy to cut features without breaking the app.

**Vertical:** Skip Epic 5 (polish) if needed - app still works
**Horizontal:** Can't skip "The Database Epic" - nothing works without it

---

## 📊 SwiftWing Epic Breakdown (Vertical Slices)

### Epic 1: Foundation (Horizontal - Exception)
**Why horizontal?** You need the skeleton first. But keep it MINIMAL.

**Delivers:** Working app that compiles, saves dummy data, fetches test JSON
**User Value:** None yet (but proves architecture works)
**Duration:** 1 week

---

### Epic 2: The Viewfinder (Vertical - Camera Feature)
**Feature:** Users can scan book spines with camera

**Vertical Slice:**
- UI: Camera preview + shutter button + processing queue
- Logic: Image capture + resize/compress
- Data: Save to temp files
- Network: ❌ Deferred to Epic 4

**Delivers:** Working scanner (no AI results yet)
**User Value:** Can capture book spine images
**Demo:** "Look, I can rapid-fire scan 10 books!"
**Duration:** 1-2 weeks

---

### Epic 3: The Library (Vertical - Display Feature)
**Feature:** Users can view and search their scanned books

**Vertical Slice:**
- UI: Library grid + search bar + detail sheets
- Logic: Query filtering + sorting
- Data: SwiftData schema + real book records
- Network: AsyncImage for cover downloads

**Delivers:** Working library with search
**User Value:** Can browse and find books
**Demo:** "Look, I have 50 books in a grid with covers!"
**Duration:** 1-2 weeks

---

### Epic 4: Talaria Integration (Vertical - AI Enrichment)
**Feature:** Scanned images get AI-enriched with metadata

**Vertical Slice:**
- UI: Progress overlays on processing queue
- Logic: SSE stream parsing + result handling
- Data: SwiftData upsert (update existing records)
- Network: Talaria API upload + SSE listener

**Delivers:** Full AI-powered scanning
**User Value:** Books automatically identified with titles, authors, covers
**Demo:** "Look, I scanned a spine and got full metadata!"
**Duration:** 1-2 weeks

---

### Epic 5: Polish (Vertical - Interaction Details)
**Feature:** App feels delightful to use

**Vertical Slice:**
- UI: Haptic feedback + animations + error states
- Logic: Edge case handling
- Data: Review-needed flags
- Network: Rate limit handling

**Delivers:** Production-quality experience
**User Value:** App feels professional
**Duration:** 1 week

---

### Epic 6: Launch (Vertical - App Store Prep)
**Feature:** App is ready for public release

**Vertical Slice:**
- UI: App icon + launch screen + onboarding
- Logic: Analytics + crash reporting
- Data: Export/import features
- Network: Production API endpoints

**Delivers:** App Store submission
**User Value:** Can download from App Store
**Duration:** 1 week

---

## 🛠️ How to Structure Epics (Vertical Slice Checklist)

### ✅ Good Vertical Slice
```
Epic: "User Registration"

Stories:
- UI: Registration form
- Logic: Validation rules
- Data: Save user to database
- Network: POST to /api/register

Result: Users can actually register!
```

### ❌ Bad Horizontal Slice
```
Epic: "Build Networking Layer"

Stories:
- Create NetworkService protocol
- Implement HTTPClient
- Add retry logic
- Write unit tests

Result: No user-facing feature (just infrastructure)
```

---

## 📐 Rules for Vertical Slicing

### 1. **One Epic = One Feature**
Each epic should answer: "What can the user DO after this epic?"

**Good:** "Users can scan books"
**Bad:** "The app has networking"

### 2. **Touch All Layers**
Even if minimal, include UI → Logic → Data → Network.

**Good:** Epic 2 saves to temp files (even though Epic 3 uses SwiftData)
**Bad:** Epic 2 skips storage entirely, forces Epic 3 to build it

### 3. **Defer Complexity**
Build the simplest version that works, iterate later.

**Good:** Epic 2 saves to temp files, Epic 3 adds SwiftData
**Bad:** Epic 2 builds full offline-first storage with conflict resolution

### 4. **Each Epic is Shippable**
You should be able to demo the feature after each epic.

**Good:** Can show working camera after Epic 2
**Bad:** Camera doesn't work until Epic 4 finishes

---

## 🎮 Example: Epic 2 as Vertical Slice

### Before (Horizontal Approach)
```
Epic 2A: Build Camera Infrastructure
- AVCaptureSession wrapper
- Image processing utilities
- Camera permission manager

Epic 2B: Build Camera UI
- Camera preview component
- Shutter button component
- Zoom/focus controls

Epic 2C: Connect Camera to Storage
- File saving logic
- Thumbnail generation
- Queue management

Result: Feature works after 3 epics (6 weeks!)
```

### After (Vertical Approach)
```
Epic 2: The Viewfinder (1 epic, 2 weeks)

US-201: Camera preview (UI + AVFoundation)
US-202: Shutter button (UI + capture logic)
US-203: Image processing (Logic + temp storage)
US-204: Processing queue (UI + state management)
US-205: Zoom/focus (UI + camera controls)
US-206: Design system (Polish)

Result: Feature works after 1 epic (2 weeks!)
```

**Difference:** 6 weeks → 2 weeks for same feature

---

## 🧩 Managing Dependencies Between Slices

### Shared Infrastructure
Some things ARE horizontal (database, networking). Build them JUST-IN-TIME.

**Example:**
- Epic 1: Minimal SwiftData (just Book model with 3 fields)
- Epic 3: Full SwiftData (add coverUrl, format, confidence, search)

**Don't build:** Full database schema in Epic 1 before you know what you need.

### Evolving Features
Vertical slices can ENHANCE previous slices.

**Example:**
- Epic 2: Save images to temp files
- Epic 4: Upload images to Talaria, then delete temp files

Epic 4 doesn't REPLACE Epic 2, it ENHANCES it.

---

## 📅 Solo Dev Sprint Planning with Vertical Slices

### Weekly Cadence
- **Sunday Night:** Pick 3-5 stories from current epic
- **During Week:** Build them
- **Next Sunday:** Review what shipped, decide what's next

### If You Fall Behind
**Horizontal approach:**
- Can't ship Epic 2 without Epic 1
- Can't ship Epic 3 without Epic 2
- Behind schedule = nothing ships

**Vertical approach:**
- Epic 2 takes longer? Ship it when ready
- Epic 3 independent? Start it in parallel
- Behind schedule? Cut Epic 5 (polish), still have working app

---

## 🚀 Momentum Through Vertical Slices

### Week 1 (Epic 1)
**Ship:** App that launches, saves dummy data
**Demo:** "Look, it compiles and saves!"
**Feeling:** ✅ Something works

### Week 2-3 (Epic 2)
**Ship:** Working camera scanner
**Demo:** "Look, I can scan books!"
**Feeling:** 🔥 This is cool!

### Week 4-5 (Epic 3)
**Ship:** Library with search
**Demo:** "Look, 100 books in a grid!"
**Feeling:** 💪 This is real!

### Week 6-7 (Epic 4)
**Ship:** AI-powered recognition
**Demo:** "Look, it knows the books!"
**Feeling:** 🤯 This is magic!

### Compare to Horizontal:
**Week 1-3:** Build all models
**Week 4-6:** Build all services
**Week 7-8:** Build all UI
**Week 9:** Connect everything
**Feeling:** 😫 Will this ever work?

---

## 🎯 TL;DR: Vertical Slice Rules

1. **One epic = One user feature**
2. **Ship working code every 1-2 weeks**
3. **Touch all layers (even if minimal)**
4. **Defer complexity to later slices**
5. **Each epic is demoable**

**Result:** You stay motivated, users get value, project makes progress.

---

**For SwiftWing:**
- Epic 1: Skeleton (horizontal, required)
- Epic 2: Camera (vertical - scan feature)
- Epic 3: Library (vertical - browse feature)
- Epic 4: AI (vertical - enrichment feature)
- Epic 5: Polish (vertical - UX feature)
- Epic 6: Launch (vertical - distribution feature)

**Each epic after #1 is a complete feature you can demo!**
