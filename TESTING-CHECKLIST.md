# SwiftWing Testing Checklist

## Epic 4 Feature Verification

This checklist ensures all Epic 4 (Talaria Integration) features remain functional after code changes.

### Camera & Capture Flow

- [ ] Camera preview loads on Camera tab
- [ ] Shutter button captures image (shows white flash)
- [ ] Image appears in processing queue
- [ ] Processing queue shows thumbnail

### SSE Streaming & AI Recognition

- [ ] Progress messages appear on queue item ("Looking...", "Reading...", "Enriching...")
- [ ] Book result appears in library after processing
- [ ] Book metadata is complete (title, author, ISBN, cover)
- [ ] Processing queue item turns green on completion
- [ ] Queue item auto-removes after 5 seconds

### Rate Limiting (429 Handling)

- [ ] Rate limit overlay appears when 429 triggered
- [ ] Countdown timer displays and updates every second
- [ ] Shutter button is disabled during rate limit
- [ ] Queued scans count shows in overlay
- [ ] Scans auto-upload when countdown expires
- [ ] Shutter button re-enables after cooldown

### Offline Queue

- [ ] "OFFLINE" indicator appears when network disconnected
- [ ] Shutter button works in offline mode
- [ ] Offline scans show gray border in queue
- [ ] Offline scan count displays in indicator
- [ ] Scans auto-upload when network restored
- [ ] Queue items show upload progress

### Duplicate Detection

- [ ] Duplicate alert appears when scanning same ISBN
- [ ] Alert shows existing book title and metadata
- [ ] "Cancel" button discards duplicate
- [ ] "Add Anyway" button allows duplicate
- [ ] "View Existing" button navigates to library (or placeholder)

### Error Handling & Retry

- [ ] Error state shows red border on queue item
- [ ] Error message displays on item
- [ ] Retry button appears on failed item
- [ ] Retry button re-uploads and opens new SSE stream
- [ ] Error haptic feedback triggers on failure

### Concurrent Stream Management

- [ ] 5+ rapid scans process without crashing
- [ ] UI remains responsive during bulk scanning
- [ ] Memory usage stays reasonable (<100 MB)
- [ ] All scans eventually complete or fail gracefully

### Resource Cleanup

- [ ] Temp JPEG files are deleted after job completion
- [ ] Server-side cleanup endpoint called (DELETE /cleanup)
- [ ] No memory leaks during 10-minute scanning session
- [ ] App backgrounding cancels active SSE streams

## Epic 1-3 Regression Tests

### Library (Epic 3)

- [ ] Library grid displays books
- [ ] Search functionality works
- [ ] Sort options work (newest, oldest, title, author)
- [ ] Book detail sheet opens on tap
- [ ] Swipe to delete works
- [ ] CSV export works

### Camera Basics (Epic 2)

- [ ] Pinch zoom works (1.0x - 4.0x)
- [ ] Tap to focus works (white brackets appear)
- [ ] Zoom level displays in top-right corner
- [ ] Focus indicator fades after 1 second

### Foundation (Epic 1)

- [ ] App launches without crashes
- [ ] Camera permission prompt shows with correct description
- [ ] Theme colors render correctly (Swiss Glass)
- [ ] SwiftData persistence works (books saved across app restarts)

## Performance Checks

- [ ] Camera cold start < 3 seconds (target: < 0.5s)
- [ ] Image processing < 500ms
- [ ] Library grid scrolls smoothly (60 FPS)
- [ ] SSE first event < 500ms

## Build Validation

- [ ] 0 compiler errors
- [ ] 0 compiler warnings
- [ ] Clean build output from xcsift

---

**Notes:**
- Run this checklist after EVERY refactoring phase
- Mark items as completed with [x]
- Document any failures in git commit messages
- Use this for manual regression testing before merges
