# Quickstart: Collapsible AI Cards

**Feature**: 030-collapsible-ai-cards

## Scope

Single-file frontend change in [frontend/lib/screens/dashboard_screen.dart](../../frontend/lib/screens/dashboard_screen.dart).

## Implementation steps

1. In `DashboardScreenState`, add:
   ```dart
   bool _aiInsightsExpanded = false;
   bool _aiWorkOrderExpanded = false;
   ```
2. Add a private widget `_CollapsibleCard({required IconData icon, required String title, required bool expanded, required VoidCallback onTap, required Widget child})` in the same file. It renders:
   - An outer `Container` reusing `AppColors.bgSurface`, `BorderRadius.circular(14)`, and the same border as existing cards.
   - A header `InkWell` (Row: icon → title → `AnimatedRotation` chevron).
   - An `AnimatedSize(duration: 200ms, curve: Curves.easeInOut)` wrapping `Visibility(visible: expanded, maintainState: true, maintainAnimation: true, child: child)`.
   - `Semantics(button: true, expanded: expanded, label: title)`.
3. In `build`, replace the current `AiInsightsCard(...)` usage with:
   ```dart
   _CollapsibleCard(
     icon: Icons.auto_awesome,
     title: 'AI Insights',
     expanded: _aiInsightsExpanded,
     onTap: () => setState(() => _aiInsightsExpanded = !_aiInsightsExpanded),
     child: AiInsightsCard(email: _email, userRole: widget.userRole),
   )
   ```
4. Replace the current `NlInputCard(...)` usage with:
   ```dart
   _CollapsibleCard(
     icon: Icons.auto_awesome,
     title: 'AI Work Order',
     expanded: _aiWorkOrderExpanded,
     onTap: () => setState(() => _aiWorkOrderExpanded = !_aiWorkOrderExpanded),
     child: NlInputCard(
       controller: _nlController,
       isGenerating: _isGenerating,
       onGenerate: _generateAiWorkOrder,
     ),
   )
   ```
5. Because the existing cards already render their own outer `Container`/border, set the `_CollapsibleCard` body padding to `EdgeInsets.zero` and either (a) drop the inner card's outer container, or (b) leave both and accept a slight nested padding (simpler, acceptable for v1). Recommended: (b).

## Manual test plan

- [ ] Open dashboard as a `supervisor` or `admin` user → both AI Insights and AI Work Order render as single-row headers.
- [ ] Tap AI Insights header → expands smoothly, filter chips and content visible. Tap again → collapses.
- [ ] Tap AI Work Order header → expands, text field/mic/Generate visible. Tap again → collapses.
- [ ] Expand AI Insights, then expand AI Work Order → both stay open independently.
- [ ] Type "test description" into AI Work Order, collapse, re-expand → text is still there.
- [ ] Tap Generate, immediately collapse the card while generation is in flight → on completion, the bottom sheet still appears (re-expand to confirm controller cleared).
- [ ] Trigger AI Insights refresh, collapse mid-load → spinner finishes; expand again to see results.
- [ ] Restart app / navigate away and back → both cards collapsed again.
- [ ] Open dashboard as `reporter` (no AI Insights card) → AI Work Order still works as a collapsible card.
- [ ] VoiceOver/TalkBack announces header as button with expanded/collapsed state.

## Out of scope

- Persisting expansion state across sessions.
- Modifying internal layout of `AiInsightsCard` or `NlInputCard`.
- Other screens.
