# claude-status-cockpit

**Live Claude Code usage in your macOS menu bar** — twin ring gauges for the
5-hour session window and 7-day week window, colored by how much you've used,
refreshed every 10 seconds straight from your running Claude Code sessions.
Plus a one-line powerline statusline for Claude Code where **color = reasoning
effort**.

| normal | running hot | stale (no live session) |
|:---:|:---:|:---:|
| ![normal](assets/rings-normal.png) | ![high](assets/rings-high.png) | ![stale](assets/rings-stale.png) |

## What you get

**Menu bar (SwiftBar plugin)**
- Twin rings: **session (5h)** and **week (7d)** used-percentage, the number
  drawn inside each ring.
- Calm, muted colors that escalate: sage `< 60%` → sand `60–84%` → **red `≥ 85%`**.
- Reset countdowns flank the rings: session time-left on the left (`3h`),
  week time-left on the right (`6d`); full-precision countdowns in the
  dropdown.
- **Live, not stale**: data comes from the JSON Claude Code feeds its
  statusline on every update, cached to disk and read every 10 s.
- **Account-aware**: the dropdown shows which account the numbers belong to.
  Log into a different account and the rings invalidate instantly, then pick
  up the new account as soon as any session reports.
- Staleness handling: if no session has reported for 10+ minutes the rings
  turn grey and the dropdown says how old the data is.
- **Notch-aware**: everything is drawn into one compact image (~61–69 pt).
  On notched MacBooks macOS silently hides the leftmost status item when the
  bar gets tight — an 89 pt variant of this item got evicted in testing, this
  layout survives. If it ever vanishes on a very crowded bar, ⌘-drag it
  further right once so another icon becomes the notch's sacrifice.

**Terminal (Claude Code statusline)**
- Single powerline strip: model name on a background colored by the current
  reasoning effort (low → blue, medium → sage, high → sand, xhigh → amber,
  max → rose), followed by repo + branch/worktree.
- This same script is what feeds the menu bar: it writes each rate-limit
  update to `~/.cache/claude-statusbar/last_stdin.json`, stamped with the
  logged-in account.

## How it works

```
Claude Code session(s)
   │  pipes statusline JSON (incl. rate_limits) on every update
   ▼
~/.claude/statusline.sh ──── renders powerline strip in the terminal
   │  atomically writes account-stamped JSON
   ▼
~/.cache/claude-statusbar/last_stdin.json
   ▲
   │  read with jq every 10 s
SwiftBar plugin (claude_usage.10s.sh)
   │  renders/caches a compact 88 px PNG (render_rings.swift)
   ▼
menu bar rings
```

No API calls, no scraping — the numbers are exactly what Claude Code itself
reports, for exactly the account you're logged into.

## Requirements

- macOS (tested on Sequoia/Tahoe-era, Apple Silicon)
- [Claude Code](https://claude.com/claude-code) (any recent version that sends
  `rate_limits` to the statusline)
- [SwiftBar](https://swiftbar.app) — `brew install --cask swiftbar`
- `jq` — `brew install jq`
- Xcode Command Line Tools (for the `swift` PNG renderer) — `xcode-select --install`
- A terminal font with powerline glyphs (e.g. any Nerd Font) for the
  statusline separator

## Install

```bash
git clone https://github.com/shtarun/claude-status-cockpit.git
cd claude-status-cockpit
./install.sh
```

The installer:
1. checks dependencies,
2. backs up any existing `~/.claude/statusline.sh`, installs this one, and
   wires `statusLine` into `~/.claude/settings.json` (never overwriting an
   existing custom command — it tells you instead),
3. installs the SwiftBar plugin + renderer and points SwiftBar at the plugin
   folder (respecting an existing plugin folder if you have one),
4. launches SwiftBar.

Rings appear after your next interaction in any Claude Code session — that's
what makes Claude Code emit the first usage report.

## Customize

- **Refresh rate**: rename `claude_usage.10s.sh` → `claude_usage.30s.sh` (the
  filename *is* the schedule, per SwiftBar convention).
- **Color thresholds**: edit `colorFor` in `swiftbar/render_rings.swift` and
  the matching fallback thresholds in the plugin, then delete
  `~/Library/Application Support/SwiftBar/cache/rings_*.png`.
- **Statusline effort colors**: edit the `case "$effort"` block in
  `statusline/statusline.sh`.

## Troubleshooting

- **Rings never appear** → interact with a Claude Code session once (the cache
  is only written when Claude Code reports usage), then check
  `~/.cache/claude-statusbar/last_stdin.json` exists.
- **Item vanished from the menu bar** → on notched MacBooks, macOS hides the
  leftmost status item when space runs out. ⌘-drag the rings further right so
  another icon becomes the sacrifice.
- **Rings grey** → no session has reported in 10+ minutes; the dropdown shows
  the data's age.
- **"Switched account — awaiting data"** → expected right after logging into a
  different account; start any session and it repopulates.
- **Image missing but text shows** → the `swift` renderer failed; run
  `swift swiftbar/render_rings.swift 50 50 /tmp/t.png` to see why (usually
  missing Command Line Tools).

Note: if you fork the drawing code, always set the PNG's point size
(`rep.size`) — without it a Retina PNG renders at double width and the item
gets notch-evicted — and keep the total item width well under ~80 pt.

## Uninstall

```bash
rm "$HOME/Library/Application Support/SwiftBar/plugins/claude_usage.10s.sh"
rm "$HOME/Library/Application Support/SwiftBar/render_rings.swift"
# restore your previous statusline from the timestamped backup:
ls ~/.claude/statusline.sh.bak.*
```

## Design history

The `docs/` folder contains the original design specs and implementation
plans, including the debugging notes for two fun macOS gotchas: SwiftBar's
~100 px image cap and notch eviction of status items.

## License

[MIT](LICENSE)
