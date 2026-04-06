Review this diff for a SwiftUI iOS 26 app (Swift 6.2, strict concurrency). The changes fix 3 bugs and remove dead code:

1. **ATS Cover URL Fix**: Talaria returns http:// Google Books cover URLs, iOS ATS blocks them. Fix adds URL.upgradedToHTTPS extension using URLComponents to rewrite http→https. Applied in AsyncImageWithLoading and ImageCacheManager.

2. **Library Filter Reset**: After approving scan results, library showed "needs review" filter active (empty library). Fix resets UserDefaults "show_review_needed" to false in all 3 approval paths.

3. **Grid Alignment**: Library grid cells had inconsistent alignment. Fix adds leading alignment, full-width covers, fixed-height title area (32pt min), top-aligned cells.

4. **Dead code removal**: Removed unused `emoji` variables and `getEmoji()` function from PerformanceLogger.

Focus on:
- Swift 6.2 concurrency safety (actors, @MainActor, Sendable)
- Any bugs or edge cases in the URL upgrade logic
- Whether the UserDefaults approach for filter reset is correct
- Grid layout correctness for varying content sizes
- Anything that could cause build warnings (project requires 0 warnings)