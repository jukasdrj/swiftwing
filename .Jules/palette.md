## 2026-02-21 - Accessibility for Interactive Overlay Cards
**Learning:** For SwiftUI `ZStack` components with background visuals and interactive overlays (like a retry button), grouping the background elements with `.accessibilityElement(children: .ignore)` and a custom label prevents fragmentation, while keeping the interactive overlay as a separate, accessible sibling.
**Action:** When making card-like views accessible, group static/status content into one focused element and keep actionable buttons as distinct siblings.
