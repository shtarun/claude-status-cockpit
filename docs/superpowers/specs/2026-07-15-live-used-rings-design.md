# Live Used-% Rings — Design

**Date:** 2026-07-15
**Status:** Approved (interval 10s, red ≥ 85% used, dim-when-stale — all confirmed by user)
**Builds on:** `2026-07-13-claude-status-cockpit-design.md`

## Problem

The Status Cockpit menu-bar rings have shown stale data since 2026-07-13. Root
cause: the rings' numbers come from `~/.cache/claude-statusbar/last_stdin.json`,
which was written by the *old* statusline pipeline. The new powerline
`~/.claude/statusline.sh` never writes it, so the cache froze at the moment of
the statusline swap. Additionally the rings show **remaining %**, while the
user thinks in **used %**, and the 30s refresh is too coarse.

## Requirements

1. Rings show **used %** for session (5h) and week (7d), colored by severity:
   sage green < 60, sand 60–84, **red ≥ 85** (calm palette, red unmissable).
2. Refresh every **10 seconds**; data must be live, not frozen.
3. Data must reflect the account logged into terminal Claude Code; surface the
   account email in the dropdown.
4. When no session has reported for > 10 min, rings render desaturated grey and
   the dropdown shows "data as of Xm ago" (age is shown in the dropdown at all
   times).
5. **Account switch:** logging into a different account in Claude Code must
   change the rings immediately — never show the previous account's numbers as
   if they were the new account's.

## Design

### Data flow

1. **`~/.claude/statusline.sh`** (+~4 lines): when stdin JSON contains
   `rate_limits.five_hour`, write the full JSON atomically (temp file in the
   same directory, then `mv`) to `~/.cache/claude-statusbar/last_stdin.json`.
   Same path the old pipeline used, so `claude-statusbar` CLI keeps working if
   ever run by hand. Atomicity matters: 6–7 parallel sessions run the
   statusline concurrently. Claude Code invokes the statusline continuously
   during active sessions, so the cache stays seconds-fresh.
   The written JSON is **stamped with the currently logged-in account**
   (`_account` = `.oauthAccount.emailAddress` from `~/.claude.json`) so
   consumers can tell whose numbers these are.
2. **SwiftBar plugin** renamed `claude_usage.10s.sh`; reads the cache directly
   with `jq` (no `claude-statusbar` spawn). Computes:
   - `s_used`, `w_used` (floored used percentages),
   - reset countdowns from the raw `resets_at` epochs (`resets_at - now`,
     rendered as `Xh Ym` / `Xm`; show `now` when ≤ 0),
   - cache age from the file mtime; `stale = age > 600s`.

### Renderer (`render_rings.swift`)

- Args become: `sessUsed weekUsed outPath [stale]`.
- Arc fills **clockwise from 12 o'clock as usage grows**; number inside the
  ring is used %.
- Colors by used %: sage `#8FBAA0` < 60, sand `#D6C486` 60–84, red `#C4524F`
  ≥ 85 (stronger than the old muted rose so "high" reads instantly).
- `stale` flag renders arc + number in desaturated grey `#8A93A0`.
- Unchanged: ~88px PNG (44pt @2×, under SwiftBar's ~100px cap), smaller font
  for 3-digit "100".

### Plugin output

- Title: rings image + `⟳<countdown>` of the **binding limit** (now the ring
  with *higher used %*), as before.
- PNG cache key: `rings_s<used>_w<used>[_stale].png` — stable unless a
  percentage or staleness flips.
- Dropdown:
  ```
  Claude usage — <email>
  Session (5h)  12% used · resets 2h 14m
  Week (7d)     85% used · resets 43m
  data as of 3s ago
  Refresh
  ```
  Email from `~/.claude.json` → `.oauthAccount.emailAddress` (fallback: omit).
- **Account-switch invalidation:** each tick the plugin compares the cache's
  `_account` stamp with the *current* `~/.claude.json` email. On mismatch the
  cached numbers are treated as invalid: title shows `⏱ –` and the dropdown
  says "switched account — awaiting data for <new email>". Fresh numbers
  appear as soon as any session under the new account reports (the first
  statusline write re-stamps the cache). Known small race: a still-running
  session's first write after the switch can carry pre-switch rate limits
  under the new stamp; it self-corrects on that session's next API response.
- Missing/unreadable cache → existing "usage unavailable" fallback line.
- Renderer failure → existing text-only fallback line (used-% colored).

## Error handling

- Concurrent statusline writes: atomic `mv`; last writer wins (same account →
  same numbers, so ordering is irrelevant).
- Cache JSON without `rate_limits`: statusline skips the write (mirrors the
  guard `claude-statusbar` itself used); plugin treats missing fields as
  unavailable.
- Clock math: countdown clamps at `now`; never shows negative.

## Testing

Manual, scripted per case:
1. Run the plugin against a fresh cache, a > 10-min-old cache (expect grey
   rings + age line), and a missing cache (expect fallback).
2. Render rings at 12/60/85/100 used — verify green/sand/red/red + fill
   direction.
3. Start a Claude session, confirm cache mtime updates within seconds and the
   menu bar follows within 10s.
4. Account switch: run the plugin against a cache whose `_account` differs
   from `~/.claude.json` — expect the "switched account — awaiting data"
   state, not the old numbers.

## Out of scope

Multiple-account switching UI, historical usage graphs, changes to the
powerline segments themselves.
