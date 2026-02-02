# SwiftWing Documentation Audit Plan

**Created:** 2026-02-01
**Goal:** Organize repository documentation, remove stale artifacts, ensure current information is accessible

## Recommendations

**Status:** READY FOR REVIEW

### HIGH PRIORITY (Blocks understanding or onboarding)

#### HP-1: Resolve AGENTS.md Duplication
**Issue:** 4 copies of AGENTS.md exist, 2 with contradictory information

**Action:**
1. **Keep:** `/AGENTS.md` (25K, Jan 30) - Most comprehensive
2. **Archive:** `/AGENTS-REALITY.md` → `.archive/analysis/agents-reality-check-jan31.md`
   - Rationale: Historical critique, valuable but not operational doc
3. **Delete:** `/docs/AGENTS.md`, `/swiftwing/AGENTS.md`, `/.claude/AGENTS.md`
   - Replace with symlinks: `ln -s ../AGENTS.md docs/AGENTS.md`
   - Or add redirect comments pointing to root `/AGENTS.md`

**Success Criteria:** Only 1 canonical AGENTS.md in root

#### HP-2: Update CURRENT-STATUS.md with Recent Work
**Issue:** Last updated Jan 25, doesn't reflect Feb 1-2 critical fixes

**Action:**
1. Add new section: "Latest Updates (Feb 1-2, 2026)"
2. Document rectangle detection fixes (double throttling + object persistence)
3. Document results fetch implementation (resultsUrl flow)
4. Update Epic 5 status (if refactoring still in progress)
5. Move old "Phase 2A Complete" content to archive or collapse

**Files to Reference:**
- DEBUGGING-VISION.md (resolution details)
- RECENT-CHANGES.md (comprehensive changelog)
- critical_bugs_task_plan.md (issue tracking)

**Success Criteria:** CURRENT-STATUS.md reflects today's state

#### HP-3: Archive Root-Level Planning Files
**Issue:** 9 planning triplets + 4 debug plans cluttering root (175KB total)

**Action:**
Move to `.archive/planning/`:

**Completed Sessions (Archive):**
- camera_orientation_* (3 files, Jan 30) → `.archive/planning/camera-rotation-fix/`
- photo_upload_failure_* (3 files, Jan 31) → `.archive/planning/photo-upload-debug/`
- task_plan.md, findings.md, progress.md (Jan 23) → `.archive/planning/epic1-foundation/`

**Recent Debug (Keep 24h, then archive):**
- critical_bugs_task_plan.md (Feb 1) - Keep temporarily
- missing_results_fetch_task_plan.md (Feb 1) - Keep temporarily
- rectangle_detection_debug_task_plan.md (Feb 1) - Keep temporarily
- **After 24h:** Move to `.archive/planning/feb1-critical-fixes/`

**Success Criteria:** < 10 markdown files in root directory

### MEDIUM PRIORITY (Organizational improvements)

#### MP-1: Create Weekly Changelog Document
**Issue:** No consolidated view of "What Changed This Week"

**Action:**
Create `CHANGELOG-WEEKLY.md` with structure:
```markdown
## Week of Feb 1-7, 2026

### Critical Fixes
- Rectangle detection (double throttling + object persistence)
- Results fetch flow (resultsUrl implementation)

### Features Added
- Real-time bounding boxes in camera view

### Documentation Updates
- DEBUGGING-VISION.md (diagnostic process)
- RECENT-CHANGES.md (comprehensive log)

### Files Archived
- (List moved planning files)
```

**Update weekly, archive monthly**

**Success Criteria:** Stakeholders can see progress at a glance

#### MP-2: Consolidate Analysis Files
**Issue:** 5 analysis files in root (FIXES-APPLIED, LSP-ERRORS-ANALYSIS, REPO-ANALYSIS, etc.)

**Action:**
1. Create `.archive/analysis/` directory
2. Move completed analyses:
   - FIXES-APPLIED.md → `.archive/analysis/fixes-jan31.md`
   - LSP-ERRORS-ANALYSIS.md → `.archive/analysis/lsp-errors-jan31.md`
   - REPO-ANALYSIS-CORRECTED.md → `.archive/analysis/repo-structure-jan31.md`
   - REPO-ANALYSIS.md → Delete (superseded by CORRECTED version)
3. Keep DEBUGGING-VISION.md in root (active reference)
4. Add `INDEX.md` in `.archive/analysis/` listing all reports

**Success Criteria:** Root has 0 "ANALYSIS" files, archive is browsable

#### MP-3: Version Control Recent Changes
**Issue:** DEBUGGING-VISION.md and RECENT-CHANGES.md not committed

**Action:**
1. Git add: `git add DEBUGGING-VISION.md RECENT-CHANGES.md`
2. Commit: `git commit -m "docs: Document Feb 1-2 critical bug fixes (rectangle detection + results fetch)"`
3. Consider adding to `.gitignore`:
   - `*_task_plan.md` (temporary planning files)
   - `*_findings.md` (temporary planning files)
   - `*_progress.md` (temporary planning files)
   - Exception: Keep committed planning files in `.archive/`

**Success Criteria:** Critical fixes documented in git history

#### MP-4: Clarify Planning File Lifecycle
**Issue:** No clear policy on when to archive planning files

**Action:**
Create `.claude/rules/documentation-lifecycle.md`:
```markdown
## Planning File Lifecycle

### Active Planning (Root Directory)
- Files: *_task_plan.md, *_findings.md, *_progress.md
- Duration: During active work (max 7 days)
- Location: Project root for easy access

### Completed Planning (Archive)
- Trigger: Task complete OR 7 days since last update
- Destination: .archive/planning/{category}/{task-name}/
- Categories: epics, user-stories, bug-fixes, investigations

### Permanent Documentation (Root/Docs)
- CURRENT-STATUS.md (living document)
- DEBUGGING-VISION.md (reference guide)
- RECENT-CHANGES.md (rolling 30-day log)
- Archive after 30 days: → .archive/history/YYYY-MM/
```

**Success Criteria:** Team knows where to find and file docs

### LOW PRIORITY (Polish)

#### LP-1: Add README.md to Root
**Issue:** No README.md in root (common first file developers look for)

**Action:**
Create `/README.md` with:
- Project overview (1 paragraph)
- Quick links: START-HERE.md, CLAUDE.md, CURRENT-STATUS.md
- Build instructions (reference CLAUDE.md section)
- License info
- Contact/contribution guidelines

**Keep it < 100 lines** (detailed info lives elsewhere)

**Success Criteria:** New developers can orient in < 2 minutes

#### LP-2: Format Consistency in Markdown
**Issue:** Inconsistent heading styles, date formats, emoji usage

**Action:**
Run markdown linter/formatter:
```bash
# Install markdownlint-cli
npm install -g markdownlint-cli

# Fix common issues
markdownlint --fix "**/*.md"
```

**Or create style guide:** `.claude/rules/markdown-style.md`

**Success Criteria:** Consistent formatting across all docs

## Execution Steps

**Status:** READY TO EXECUTE (Requires user approval)

### Phase 1: Critical Cleanup (15 minutes)

**HP-1: Resolve AGENTS.md Duplication**
```bash
# 1. Archive AGENTS-REALITY.md
mkdir -p .archive/analysis
git mv AGENTS-REALITY.md .archive/analysis/agents-reality-check-jan31.md

# 2. Remove duplicate AGENTS.md files
rm docs/AGENTS.md swiftwing/AGENTS.md .claude/AGENTS.md

# 3. Create reference note in each location
echo "# AGENTS.md has moved to /AGENTS.md (root)" > docs/AGENTS-LINK.md
echo "See: /AGENTS.md for full documentation" >> docs/AGENTS-LINK.md

# 4. Commit
git add -A
git commit -m "docs: Consolidate AGENTS.md to single canonical location"
```

**HP-2: Update CURRENT-STATUS.md**
```bash
# Manual edit required - add section:
# ## Latest Updates (Feb 1-2, 2026)
# - Rectangle detection fixes (see DEBUGGING-VISION.md)
# - Results fetch implementation (see RECENT-CHANGES.md)
# - Build: 0 errors, 0 warnings ✅
```

**HP-3: Archive Root-Level Planning Files**
```bash
# Create archive directories
mkdir -p .archive/planning/camera-rotation-fix
mkdir -p .archive/planning/photo-upload-debug
mkdir -p .archive/planning/epic1-foundation

# Move completed planning files
git mv camera_orientation_*.md .archive/planning/camera-rotation-fix/
git mv photo_upload_failure_*.md .archive/planning/photo-upload-debug/
git mv task_plan.md findings.md progress.md .archive/planning/epic1-foundation/

# Commit
git add -A
git commit -m "docs: Archive completed planning files (camera rotation, photo upload, epic 1)"
```

### Phase 2: Version Control & Organization (10 minutes)

**MP-3: Commit Recent Documentation**
```bash
# Add untracked critical docs
git add DEBUGGING-VISION.md RECENT-CHANGES.md

# Commit
git commit -m "docs: Document Feb 1-2 critical bug fixes

- Rectangle detection: double throttling + object persistence fixes
- Results fetch: resultsUrl implementation
- Includes diagnostic procedures and resolution steps"
```

**MP-2: Consolidate Analysis Files**
```bash
# Create analysis archive
mkdir -p .archive/analysis

# Move completed analyses
git mv FIXES-APPLIED.md .archive/analysis/fixes-jan31.md
git mv LSP-ERRORS-ANALYSIS.md .archive/analysis/lsp-errors-jan31.md
git mv REPO-ANALYSIS-CORRECTED.md .archive/analysis/repo-structure-jan31.md
rm REPO-ANALYSIS.md  # Superseded by CORRECTED version

# Commit
git add -A
git commit -m "docs: Archive completed analysis files"
```

### Phase 3: Documentation Structure (15 minutes)

**MP-1: Create Weekly Changelog**
```bash
# Create CHANGELOG-WEEKLY.md with template (see MP-1 in recommendations)
# Manual content writing required
```

**MP-4: Document Lifecycle Policy**
```bash
# Create .claude/rules/documentation-lifecycle.md
# Content provided in MP-4 recommendation above
```

**LP-1: Add README.md**
```bash
# Create /README.md with project overview
# Quick links to START-HERE.md, CLAUDE.md, CURRENT-STATUS.md
```

### Phase 4: Temporary Files Decision (Manual Review Required)

**Recent Debug Files (Keep or Archive?):**
- critical_bugs_task_plan.md (Feb 1, 7.6K)
- missing_results_fetch_task_plan.md (Feb 1, 9.6K)
- rectangle_detection_debug_task_plan.md (Feb 1, 4.1K)

**Options:**
1. **Keep 24-48h** for reference during production testing
2. **Archive immediately** to `.archive/planning/feb1-critical-fixes/`

**User Decision Required:** Based on whether these are still actively referenced

### Phase 5: Optional Polish (Low Priority)

**LP-2: Format Consistency**
```bash
# Install markdown linter
npm install -g markdownlint-cli

# Run formatter (dry run first)
markdownlint "**/*.md"

# Apply fixes
markdownlint --fix "**/*.md"
```

## Rollback Plan

If any cleanup causes issues:

```bash
# Undo last commit
git reset --soft HEAD~1

# Restore deleted files
git checkout HEAD -- <file-path>

# Restore moved files
git mv .archive/path/file.md original/path/file.md
```

## Validation Checklist

After execution, verify:
- [ ] Only 1 AGENTS.md exists (root level)
- [ ] CURRENT-STATUS.md reflects Feb 1-2 work
- [ ] < 15 markdown files in root directory
- [ ] DEBUGGING-VISION.md and RECENT-CHANGES.md committed
- [ ] .archive/ structure browsable with INDEX.md files
- [ ] Build still succeeds (0 errors, 0 warnings)
- [ ] No broken links in documentation

---

**Last Updated:** 2026-02-01 (Execution plan complete)
