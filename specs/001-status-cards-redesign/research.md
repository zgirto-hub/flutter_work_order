# Research: System Status Cards Redesign

## Current Layout Analysis

### _SystemCard (lines 1151-1247)

**Current structure**:
- Container: `padding: EdgeInsets.all(8)`, borderRadius 8, border 0.5
- Column layout (vertical stacking):
  - Row 1: system name (fontSize 11) + optional SAT tag (fontSize 7) + status dot (7x7)
  - SizedBox(height: 4)
  - Row 2: status badge ("OK"/"Issue" text in colored container, fontSize 9, padding h:6 v:2)
- Grid: `childAspectRatio: 1.6`, crossAxisCount: 3, spacing: 8

**Problem**: The status badge on a second row doubles the vertical content.
The `childAspectRatio: 1.6` forces cards to be taller than needed for
single-line content.

**Design decision — inline status approach**:
- Merge the status indicator into the name row instead of a separate
  badge row below.
- Use the status dot color (already present) as the primary indicator.
- Move the "OK"/"Issue" text into the same row as the name, right-aligned
  next to the status dot, or replace the separate badge with just the
  colored dot (which already communicates status).
- Increase `childAspectRatio` to ~2.8-3.2 (wider, shorter cards).
- Reduce container padding from 8 to 6.

**Rationale**: Eliminating the second row cuts card height by ~40%.
The status dot color (green/red) is already the primary visual signal;
the text badge ("OK"/"Issue") is redundant when paired with the dot.
However, to satisfy FR-002 (retain all information), keep the text as
a small label next to the dot.

**Alternatives considered**:
- Keep two-row layout, just reduce spacing → only ~15% savings, insufficient
- Remove status text entirely → violates FR-002
- Add more columns → rejected per spec assumptions

### _ExpandableGroup (lines 1004-1145)

**Current structure**:
- Header: padding h:12 v:10, borderRadius 10, arrow icon + title + issue badge
- Expanded content: padding-top 10, same GridView as main (aspectRatio 1.6)
- SizedBox(height: 12) between groups

**Design decision**:
- Reduce header padding from v:10 to v:8
- Use the same increased childAspectRatio as the main grid
- Reduce gap between groups from 12 to 8

**Rationale**: Groups inherit the compact card change automatically
since they use the same `_SystemCard` widget. Only header and spacing
adjustments are needed.

### _HistoryCard (lines 1251-1388)

**Current structure**:
- Container: margin-bottom 8, padding 12, borderRadius 10
- Row: status dot (8x8) + SizedBox(10) + Expanded Column:
  - Row: system name (fontSize 13) + Spacer + date (fontSize 11) + menu (24x24)
  - If notes: SizedBox(2) + notes text (fontSize 12, single line ellipsis)
  - SizedBox(2) + status label ("Resolved"/"Unresolved", fontSize 11)

**Design decision**:
- Reduce container padding from 12 to 8-10
- Reduce margin-bottom from 8 to 6
- Reduce status dot from 8x8 to 6x6
- Move the status label inline with the name row (as a small colored
  badge) instead of a separate row, to save one vertical line
- Reduce font sizes slightly: name 12, date 10, notes 11, status 10

**Rationale**: Each card currently occupies ~56-64px. Reducing padding
and consolidating rows should bring it to ~36-44px (~35% reduction).

**Alternatives considered**:
- ListView with separator → loses the container card feel, rejected
- Horizontal scroll → confusing for a status list, rejected

## Summary of Approach

| Widget | Current Height (est.) | Target Height (est.) | Reduction |
|--------|----------------------|---------------------|-----------|
| _SystemCard | ~52px (aspect 1.6) | ~30px (aspect ~2.8) | ~42% |
| _ExpandableGroup header | ~48px | ~40px | ~17% |
| _HistoryCard | ~60px | ~40px | ~33% |

All changes stay within `system_status_screen.dart`. No new widgets,
files, or dependencies needed.
