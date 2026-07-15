# Claude Status Cockpit — Design Spec

**Date:** 2026-07-13
**Author:** brainstormed with Claude
**Status:** Draft for review

## Problem

The user runs 6–7 Claude Code sessions in parallel as **split panes in a single
Ghostty window**. The current statusline prints **two lines per pane** (a
repo/branch prefix line + the `claude-statusbar` usage/model line). Across 7
splits that is a lot of vertical space spent on status.

Two things the user wants to read *at a glance* are buried in that text:

1. **Usage left** (session 5h + weekly 7d) — wanted up in the macOS menu bar,
   next to battery / Control Center, out of the terminal entirely.
2. **Reasoning effort** per session — wanted as a **single color** so a pane's
   effort is legible without reading words.

## Goals

- Move usage out of the terminal into a **macOS menu-bar item**: two ring
  gauges showing **percent remaining** for session (5h) and week (7d).
- Collapse the per-pane statusline to **one line** where **color encodes
  effort** and the **text is model name + folder/worktree/branch**, rendered as
  a **powerline** strip.
- Reclaim one full line of vertical space in every split.
- Two pieces are **independent** — either can ship alone.

## Non-goals

- No native/compiled menu-bar app (SwiftBar plugin is enough).
- No tinting of the Ghostty pane background (considered; rejected for
  readability — revisit later if desired).
- No change to Ghostty keybinds or split config.

## Data sources (verified)

- **Effort** — `effort.level` in the statusLine JSON piped to
  `statusline.sh` on stdin. Values: `low | medium | high | xhigh | max`.
  Reflects the **live** session value including mid-session `/effort`. Absent
  when the model doesn't support effort. *(No hooks needed.)*
- **Model name** — `model.display_name` in the same statusLine JSON.
- **Repo / branch / worktree** — already derived by the existing
  `statusline.sh` (`workspace.repo.name`, `workspace.git_worktree`, and git in
  `current_dir`).
- **Usage** — `printf '{}' | claude-statusbar --json-output` runs **outside a
  session** (it needs *some* stdin — empty JSON suffices — then reads real
  rate-limit data from its own official-source cache) and returns:
  ```json
  {"rate_limits":{"five_hour":{"used_percentage":93,"reset_time":"10m"},
                  "seven_day":{"used_percentage":84,"reset_time":"2d10h"}}}
  ```
  Remaining = `100 - used_percentage`.

## Color ramp (effort)

Cool = light thinking → hot = heavy. Shared by both pieces. **Muted,
low-saturation tones** — the strips sit in peripheral vision across 7 panes all
day, so the palette is deliberately gentle (dusty / desaturated), not vivid.

| Effort  | Hex       | Tone         | Meaning              |
|---------|-----------|--------------|----------------------|
| low     | `#8AA9C9` | dusty blue   | quick edits          |
| medium  | `#8FBAA0` | sage green   | steady work          |
| high    | `#D6C486` | muted sand   | real reasoning       |
| xhigh   | `#D9A175` | soft clay    | user default / ultracode |
| max     | `#CC8385` | dusty rose   | full send            |
| (absent)| `#8A93A0` | muted slate  | model has no effort param |

All ramp tones are light enough that **near-black text (`#0b0c10`) is legible
on every one** — no per-effort text-color switching needed.

Usage rings use a semantic (not effort) scale on **remaining**, drawn from the
same muted family: sage `> 30%` · sand `10–30%` · dusty rose `< 10%`.

---

## Piece A — Menu-bar usage (twin rings)

### Host
**SwiftBar** (`brew install --cask swiftbar`). Actively maintained xbar
successor; runs a plugin script on an interval and renders its output in the
menu bar.

### Plugin
`~/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh`
(the `.30s.` in the filename sets a 30-second refresh).

Flow each tick:
1. Run `claude-statusbar --json-output --no-auto-update --hide-pet --no-color`.
   - `--no-auto-update` avoids a network/update hit every 30s.
2. Parse `five_hour.used_percentage`, `seven_day.used_percentage`, and the two
   `reset_time` strings with `jq`.
3. Compute `sess_left = 100 - five_hour_used`, `week_left = 100 - seven_day_used`.
4. Pick the **binding** limit (lower remaining) and take its `reset_time` string.
5. **Render two ring gauges + numbers + the binding reset countdown into a
   PNG**, base64 it, and emit the SwiftBar menu-bar line: `| image=<base64> ...`.
6. Emit dropdown rows (see below).

### Ring rendering
The menu bar shows an **image** (rings can't be drawn with text). A small
**Swift + CoreGraphics** helper (`render_rings.swift`, no external deps) draws:

```
◔ 7%   ◔ 16%   ⟳10m   <- two ring gauges + one adaptive reset countdown
```

The trailing `⟳<time>` is the reset countdown of the **binding limit** — the
one with lower remaining % (the limit you're actually waiting on). Drawn in
muted slate `#8A93A0`. It updates automatically: session reset when session is
tighter, week reset when week is tighter. Both resets always appear in the
dropdown regardless. The renderer takes the reset string as an optional 4th arg
(`render_rings <sess> <week> <out> [resetLabel]`); with no 4th arg it draws
rings only.
- Each ring: filled arc = **remaining** fraction, in the semantic color for
  that value; track = 28% grey. Center hole matches menu-bar background
  (transparent), so it adapts to light/dark automatically.
- The `%` number is drawn beside each ring in the ring's color.
- Output a `@2x` retina PNG sized for a 22px menu-bar height; SwiftBar treats a
  templated/plain PNG correctly in both appearances (colors are intentional, so
  it is **not** a template image — it keeps its hues).

**Performance:** rounding both percentages to the nearest 1% still yields cheap
draws, but to keep refreshes instant we **cache** the PNG on disk keyed by
`s{sess_left}-w{week_left}` under
`~/Library/Application Support/SwiftBar/cache/`. A tick only invokes Swift on a
cache miss. Fallback: if Swift rendering fails, emit a text line
`⏱ 7% ⌛ 16%` colored via SwiftBar's `color=` so the item never goes blank.

### Dropdown (on click)
```
Claude usage
---
Session (5h)   7% left · resets 10m
Week (7d)     16% left · resets 2d10h
---
Refresh | refresh=true
```

### Edge cases
- `claude-statusbar` returns `success:false` or empty → show `⏱ –` grey and a
  dropdown line "usage unavailable (no recent session data)".
- Data can go stale between sessions; acceptable since the user always has
  sessions running. No extra freshness logic.

---

## Piece B — Effort powerline statusline (one line)

Rewrite `~/.claude/statusline.sh` to emit **a single powerline line**. Usage
text is dropped (it now lives in the menu bar), so `claude-statusbar` is no
longer called from the statusline.

### Layout
```
[ Opus 4.8 ][ claude-ghostty  on main ]
   ^effort-colored bg          ^dark bg (#232833), light text
```
- **Segment 1** — background = **effort color** (muted); text = **model display
  name** in near-black `#0b0c10` (legible on every ramp tone, so no per-effort
  text-color switching).
- **Segment 2** — dark background `#232833`, light text `#aeb7c4`; text =
  `repo on branch`, or `repo wt:<worktree>` in a linked worktree. Falls back to
  directory basename when no repo (existing behavior).
- **Separator** — powerline right-triangle `U+E0B0` (` `), fg = previous
  segment bg, bg = next segment bg. Ghostty renders this glyph natively; no
  Nerd Font required.
- A trailing `U+E0B0` in **segment 2's dark color** (`#232833`) closes the strip
  against the terminal background (powerline convention: the closer takes the
  preceding segment's bg as its fg).

### Effort handling
- Read `.effort.level` from stdin JSON → map to color via the ramp table.
- **Absent** (`effort` missing) → use the muted slate `#8A93A0` "no effort
  param" color; segment 1 still shows the model.
- Effort is conveyed by **color only** — no effort word in the text (decided).

### Implementation notes
- Emit 24-bit ANSI: `\e[38;2;R;G;Bm` (fg) and `\e[48;2;R;G;Bm` (bg), reset
  `\e[0m`. A small `hex_to_rgb` shell helper converts the ramp hexes.
- Keep the existing repo/worktree/branch derivation from the current script;
  only the **output rendering** and the **removal of the second usage line**
  change.
- Single line only → Claude Code renders it as a one-line statusline, saving a
  row per pane.

---

## File inventory

| Path | Change |
|------|--------|
| `~/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh` | new — usage plugin |
| `~/Library/Application Support/SwiftBar/render_rings.swift` | new — ring PNG renderer (kept OUT of `plugins/` so SwiftBar doesn't run it as a plugin) |
| `~/.claude/statusline.sh` | rewrite — powerline effort line, drop usage line |
| `~/.claude/statusline.sh.bak` | backup of current script before rewrite |
| SwiftBar app | install via Homebrew cask; set to launch at login |

## Verification

- **Menu bar:** install SwiftBar, drop the plugin, confirm two rings appear with
  correct remaining % and colors; click → dropdown shows reset times; kill all
  sessions and confirm graceful "unavailable" state; confirm a cache hit renders
  with no visible Swift spawn.
- **Statusline:** run a session at each effort (`/effort low|medium|high|xhigh|max`)
  and confirm segment-1 color changes live; confirm model name + repo/branch and
  the worktree variant render; confirm powerline glyphs draw in Ghostty; confirm
  output is exactly one line; confirm a model without effort shows grey.

## Rollback

- Statusline: `mv ~/.claude/statusline.sh.bak ~/.claude/statusline.sh`.
- Menu bar: remove the plugin file (or quit SwiftBar); nothing else touched.

## Resolved decisions

1. Ring gauges fill by **remaining** (usage left).
2. Install **SwiftBar** via `brew install --cask swiftbar`, launch at login.
3. Effort is **color only** — no colorblind text label.
