# SwiftWing deep analysis

Pass-by-pass notes for the primary functions of the app. This directory is the record. Do not rely on chat history.

## Where things go

| File | What it holds |
|---|---|
| `00-ledger.md` | Open todos, cross-pass questions, and decisions that outlive a single pass |
| `01-launch-onboarding-permission.md` | Pass 1 — launch, onboarding, permission |
| `02-shelf-shutter-camera-session.md` | Pass 2 — shutter and session |
| `03-on-device-image-prep.md` | Pass 3 — on-device image prep |
| `04-shelf-to-books.md` | Pass 4 — upload, poll, N books |
| `05-draw-detected-books.md` | Pass 5 — drawing detected books |
| `06-review-recovery-duplicates.md` | Pass 6 — review, recovery, duplicates |
| `07-save-into-catalog.md` | Pass 7 — save into the catalog |
| `08-library-browse.md` | Pass 8 — library browse |
| `09-offline-queue-rate-limit.md` | Pass 9 — offline queue and rate limit |
| `10-resolution-workflow.md` | Order for closing the ledger, with the note, test, and doc update for each slice |

A pass is done when its findings file answers all five questions and any new todo is a row in `00-ledger.md`. Fixes are separate work. A findings file records what is true. It does not change behavior.

## Questions every pass answers

1. What event starts this function, and which type owns it?
2. What are the inputs and outputs, with the real type names?
3. Which failures are handled, and which are only logged?
4. Which behavior has a test, and which behavior only a device or a fresh install can show?
5. What is the one structural risk?

## Pass order

1. Launch, onboarding, camera permission — `01-` (2026-09-24)
2. Shelf shutter and camera session — `02-` (2026-09-24)
3. On-device image prep — `03-` (2026-09-24)
4. Shelf photo → book results — `04-` (2026-09-24)
5. Drawing detected books — `05-` (2026-09-24). Boxes treated as absent.
6. Review, edit, manual recovery, duplicates — `06-` (2026-09-24)
7. Save into the catalog — `07-` (2026-09-24)
8. Library browse — `08-` (2026-09-24)
9. Offline queue and rate limit — `09-` (2026-09-24)
