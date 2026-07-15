# Claude Status Cockpit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Claude Code usage into the macOS menu bar as twin ring gauges, and collapse each Ghostty split's statusline to a single powerline line whose color encodes reasoning effort.

**Architecture:** Two independent pieces. (A) A SwiftBar plugin polls `claude-statusbar --json-output` every 30s, renders two ring gauges to a cached PNG via a dependency-free Swift/CoreGraphics helper, and shows it in the menu bar. (B) A rewrite of `~/.claude/statusline.sh` reads `effort.level` and `model.display_name` from the statusLine JSON it already receives and prints one powerline strip: an effort-colored segment with the model name, then a dark segment with repo + branch/worktree.

**Tech Stack:** SwiftBar (Homebrew cask), Swift (system `swift`, AppKit/CoreGraphics — no external deps), bash 3.2, `jq`, 24-bit ANSI, Ghostty (native powerline glyph rendering).

## Global Constraints

- **Shell:** system `/bin/bash` is **3.2.57**. No `\u` escapes, no associative arrays, no `${var^^}`. Use octal `printf` for the powerline glyph and `$((16#..))` for hex→decimal.
- **No external runtime deps:** no pip/npm. Ring rendering uses system `swift` only.
- **`claude-statusbar` path:** `/Users/shtarun/.local/share/uv/tools/claude-statusbar/bin/claude-statusbar`.
- **Muted effort palette (verbatim):** low `#8AA9C9` · medium `#8FBAA0` · high `#D6C486` · xhigh `#D9A175` · max `#CC8385` · absent `#8A93A0`.
- **Usage semantic palette (on *remaining*):** sage `#8FBAA0` `>30%` · sand `#D6C486` `10–30%` · rose `#CC8385` `<10%`.
- **Statusline segment-2 colors:** bg `#232833` (rgb 35;40;51), fg `#aeb7c4` (rgb 174;183;196). Effort-segment text ink `#0b0c10` (rgb 11;12;16).
- **Rings fill by REMAINING** (`100 - used_percentage`). Effort is **color only** — no effort word in statusline text.
- **This directory is not a git repo** — there are no commit steps; each task ends with a verification checkpoint. Originals are backed up before rewrite.

---

### Task 1: Install SwiftBar and locate the plugin directory

**Files:**
- No files created; installs the SwiftBar app and creates its plugin directory.

**Interfaces:**
- Produces: plugin directory path `~/Library/Application Support/SwiftBar/plugins/` used by Tasks 2 & 3.

- [ ] **Step 1: Confirm the usage data source works standalone**

Run (must pipe empty JSON — `claude-statusbar` refuses to run with no stdin):
```bash
printf '{}' | /Users/shtarun/.local/share/uv/tools/claude-statusbar/bin/claude-statusbar \
  --json-output --no-auto-update --hide-pet --no-color | jq '.rate_limits'
```
Expected: a JSON object with `five_hour.used_percentage` and `seven_day.used_percentage` integers. If it errors, stop — the whole menu-bar piece depends on this.

- [ ] **Step 2: Install SwiftBar**

Run:
```bash
brew install --cask swiftbar
```
Expected: cask installs `SwiftBar.app` into `/Applications`.

- [ ] **Step 3: Launch SwiftBar and set the plugin folder**

Open SwiftBar (`open -a SwiftBar`). On first launch it asks for a plugin folder — choose/create:
```bash
mkdir -p "$HOME/Library/Application Support/SwiftBar/plugins"
```
Set that as the plugin folder in the SwiftBar prompt. Also enable **Launch at Login** (SwiftBar → Preferences).

- [ ] **Step 4: Verify the plugin directory exists**

Run:
```bash
ls -d "$HOME/Library/Application Support/SwiftBar/plugins" && echo OK
```
Expected: prints the path and `OK`.

---

### Task 2: Swift ring renderer

**Files:**
- Create: `~/Library/Application Support/SwiftBar/render_rings.swift`

**Interfaces:**
- Produces: a CLI `swift render_rings.swift <sessLeft> <weekLeft> <outPath>` that writes a PNG of two ring gauges + `%` labels. Consumed by Task 3.

- [ ] **Step 1: Write a verification that fails (renderer absent)**

Run:
```bash
swift "$HOME/Library/Application Support/SwiftBar/render_rings.swift" 7 16 /tmp/rings_test.png; echo "exit=$?"
```
Expected: fails (file not found / non-zero), and `/tmp/rings_test.png` does not exist.

- [ ] **Step 2: Write the renderer**

Create `~/Library/Application Support/SwiftBar/render_rings.swift`:
```swift
import AppKit

// args: sessLeft weekLeft outPath [resetLabel]  (percentages 0-100; resetLabel optional)
let a = CommandLine.arguments
guard a.count >= 4, let sess = Int(a[1]), let week = Int(a[2]) else {
    FileHandle.standardError.write("usage: render_rings <sessLeft> <weekLeft> <out.png> [resetLabel]\n".data(using: .utf8)!)
    exit(1)
}
let outPath = a[3]
let reset = a.count >= 5 ? a[4] : ""

let scale: CGFloat = 2.0
let logicalH: CGFloat = 22
let ringSize: CGFloat = 15
let lineW: CGFloat = 3
let labelW: CGFloat = 26
let gap: CGFloat = 8
let pad: CGFloat = 2
let slate = NSColor(srgbRed: 0x8A/255, green: 0x93/255, blue: 0xA0/255, alpha: 1)
let resetFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
let resetStr: NSAttributedString? = reset.isEmpty ? nil :
    NSAttributedString(string: "⟳\(reset)", attributes: [.font: resetFont, .foregroundColor: slate])
let resetGap: CGFloat = reset.isEmpty ? 0 : 8
let resetW: CGFloat = resetStr?.size().width ?? 0
let W = pad + ringSize + 3 + labelW + gap + ringSize + 3 + labelW + resetGap + resetW + pad

func colorFor(_ remaining: Int) -> NSColor {
    if remaining > 30 { return NSColor(srgbRed: 0x8F/255, green: 0xBA/255, blue: 0xA0/255, alpha: 1) } // sage
    if remaining >= 10 { return NSColor(srgbRed: 0xD6/255, green: 0xC4/255, blue: 0x86/255, alpha: 1) } // sand
    return NSColor(srgbRed: 0xCC/255, green: 0x83/255, blue: 0x85/255, alpha: 1)                        // rose
}

let pxW = Int(W * scale), pxH = Int(logicalH * scale)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: scale, y: scale)
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsctx

func drawRing(cx: CGFloat, cy: CGFloat, remaining: Int) {
    let r = ringSize/2 - lineW/2
    let track = NSBezierPath()
    track.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: 360)
    NSColor(white: 0.5, alpha: 0.28).setStroke()
    track.lineWidth = lineW
    track.stroke()
    let sweep = CGFloat(max(0, min(100, remaining))) / 100.0 * 360.0
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                  startAngle: 90, endAngle: 90 - sweep, clockwise: true)
    colorFor(remaining).setStroke()
    arc.lineWidth = lineW
    arc.lineCapStyle = .round
    arc.stroke()
}

func drawLabel(x: CGFloat, cy: CGFloat, pct: Int, remaining: Int) {
    let s = "\(max(0, min(100, pct)))%"   // clamp label to match the clamped arc
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: colorFor(remaining)
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    str.draw(at: NSPoint(x: x, y: cy - str.size().height/2))
}

let cy = logicalH/2
var cx: CGFloat = pad + ringSize/2
drawRing(cx: cx, cy: cy, remaining: sess)
drawLabel(x: cx + ringSize/2 + 3, cy: cy, pct: sess, remaining: sess)
cx += ringSize/2 + 3 + labelW + gap + ringSize/2
drawRing(cx: cx, cy: cy, remaining: week)
drawLabel(x: cx + ringSize/2 + 3, cy: cy, pct: week, remaining: week)
if let rs = resetStr {
    let rx = cx + ringSize/2 + 3 + labelW + resetGap
    rs.draw(at: NSPoint(x: rx, y: cy - rs.size().height/2))
}

NSGraphicsContext.current = nil
guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
rep.size = NSSize(width: W, height: logicalH)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: outPath)) } catch { exit(1) }
```

- [ ] **Step 3: Run the renderer and verify it produces a PNG**

Run:
```bash
swift "$HOME/Library/Application Support/SwiftBar/render_rings.swift" 7 16 /tmp/rings_test.png; echo "exit=$?"
sips -g pixelWidth -g pixelHeight /tmp/rings_test.png
```
Expected: `exit=0`; `sips` reports a PNG roughly `~186 x 44` pixels (2× the ~93×22 logical size). First `swift` compile may take a few seconds.

- [ ] **Step 4: Render the 4-arg form with a reset countdown**

Run:
```bash
swift "$HOME/Library/Application Support/SwiftBar/render_rings.swift" 7 16 /tmp/rings_reset.png "10m"; echo "exit=$?"
sips -g pixelWidth /tmp/rings_reset.png
```
Expected: `exit=0`; the PNG is **wider** than the 3-arg image (it now includes `⟳10m` text after the rings).

- [ ] **Step 5: Eyeball both images**

Run:
```bash
open /tmp/rings_test.png /tmp/rings_reset.png
```
Expected: two ring gauges, left ~7% arc in rose, right ~16% arc in sand, each with a `%` label in the matching muted color; the second image also shows `⟳10m` in muted grey to the right. If the arcs look inverted (filling by *used*), stop and recheck — they must fill by remaining.

- [ ] **Step 6: Checkpoint**

Renderer works standalone in both 3-arg and 4-arg forms. Clean up: `rm -f /tmp/rings_test.png /tmp/rings_reset.png`.

---

### Task 3: SwiftBar usage plugin

**Files:**
- Create: `~/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh`

**Interfaces:**
- Consumes: `claude-statusbar` JSON; `render_rings.swift` from Task 2.
- Produces: a SwiftBar menu-bar item (image of twin rings) + click-through dropdown. The `.30s.` in the filename sets a 30-second refresh.

- [ ] **Step 1: Write a verification that fails (plugin absent)**

Run:
```bash
P="$HOME/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh"; test -x "$P" && echo present || echo absent
```
Expected: `absent`.

- [ ] **Step 2: Write the plugin**

Create `~/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh`:
```bash
#!/bin/bash
# <xbar.title>Claude Usage</xbar.title>
# <xbar.desc>Session (5h) + week (7d) usage remaining as twin ring gauges.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:$PATH"

STATUSBAR="/Users/shtarun/.local/share/uv/tools/claude-statusbar/bin/claude-statusbar"
DIR="$HOME/Library/Application Support/SwiftBar"
RENDERER="$DIR/render_rings.swift"   # kept OUT of plugins/ so SwiftBar does not run it as a plugin
CACHE="$DIR/cache"
mkdir -p "$CACHE"
# Reset countdown is in the cache filename, so entries churn over time — prune old ones.
find "$CACHE" -name 'rings_*.png' -mtime +1 -delete 2>/dev/null

# claude-statusbar refuses to run without stdin ("No stdin data"); feed it empty
# JSON. It still reads real rate-limit data from its own official-source cache.
json="$(printf '{}' | "$STATUSBAR" --json-output --no-auto-update --hide-pet --no-color 2>/dev/null)"
ok="$(printf '%s' "$json" | jq -r '.success // false' 2>/dev/null)"

if [ "$ok" != "true" ]; then
  echo "⏱ – | color=#8A93A0 font=Menlo size=13"
  echo "---"
  echo "Claude usage unavailable (no recent session data)"
  echo "Refresh | refresh=true"
  exit 0
fi

s_used="$(printf '%s' "$json" | jq -r '(.rate_limits.five_hour.used_percentage // 0) | floor')"
w_used="$(printf '%s' "$json" | jq -r '(.rate_limits.seven_day.used_percentage // 0) | floor')"
s_reset="$(printf '%s' "$json" | jq -r '.rate_limits.five_hour.reset_time // "?"')"
w_reset="$(printf '%s' "$json" | jq -r '.rate_limits.seven_day.reset_time // "?"')"
s_left=$(( 100 - s_used ))
w_left=$(( 100 - w_used ))

# Binding limit = the one with lower remaining %; surface its reset countdown.
if [ "$s_left" -le "$w_left" ]; then bind_reset="$s_reset"; else bind_reset="$w_reset"; fi

# Cache key includes the reset label so the countdown stays current.
safe_reset="$(printf '%s' "$bind_reset" | tr -c 'A-Za-z0-9' '_')"
img="$CACHE/rings_s${s_left}_w${w_left}_${safe_reset}.png"
[ -f "$img" ] || swift "$RENDERER" "$s_left" "$w_left" "$img" "$bind_reset" 2>/dev/null

if [ -f "$img" ]; then
  b64="$(base64 < "$img" | tr -d '\n')"
  echo " | image=$b64"
else
  scol="#8FBAA0"; [ "$s_left" -le 30 ] && scol="#D6C486"; [ "$s_left" -lt 10 ] && scol="#CC8385"
  echo "⏱ ${s_left}% ⌛ ${w_left}% ⟳${bind_reset} | color=$scol font=Menlo size=13"
fi

echo "---"
echo "Claude usage"
echo "Session (5h)  ${s_left}% left · resets ${s_reset} | font=Menlo"
echo "Week (7d)     ${w_left}% left · resets ${w_reset} | font=Menlo"
echo "---"
echo "Refresh | refresh=true"
```

- [ ] **Step 3: Make it executable**

Run:
```bash
chmod +x "$HOME/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh"
```

- [ ] **Step 4: Run the plugin directly and verify output shape**

Run:
```bash
"$HOME/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh" | head -6
```
Expected: first line is either ` | image=<long base64>` (rings rendered) or the `⏱ NN% ⌛ NN%` fallback; then a `---`; then `Claude usage`; then the two `Session`/`Week` rows with reset times. No `jq: error` lines.

- [ ] **Step 5: Verify the cache populated**

Run:
```bash
ls "$HOME/Library/Application Support/SwiftBar/cache/"
```
Expected: at least one `rings_sNN_wNN_<reset>.png` (e.g. `rings_s7_w16_10m.png`). A second plugin run with the same percentages + reset must NOT re-invoke swift (cache hit) — confirm by timing:
```bash
time "$HOME/Library/Application Support/SwiftBar/plugins/claude_usage.30s.sh" >/dev/null
```
Expected: second run is fast (well under a second) since it skips Swift.

- [ ] **Step 6: Refresh SwiftBar and eyeball the menu bar**

Run:
```bash
open "swiftbar://refreshallplugins"
```
Expected: twin rings appear in the menu bar near Control Center. Click → dropdown shows the two rows + Refresh.

- [ ] **Step 7: Tune size if needed**

If the menu-bar image looks too tall or too short, adjust `logicalH` / `scale` in `render_rings.swift`, delete the cache (`rm -f "$HOME/Library/Application Support/SwiftBar/cache/"*.png`), and refresh. Target: rings sit comfortably within the ~22pt menu-bar height.

- [ ] **Step 8: Checkpoint**

Menu-bar piece complete and independent of any session.

---

### Task 4: Powerline effort statusline

**Files:**
- Modify: `~/.claude/statusline.sh` (full rewrite)
- Create: `~/.claude/statusline.sh.bak` (backup of current)

**Interfaces:**
- Consumes: the statusLine JSON on stdin (`model.display_name`, `effort.level`, `workspace.repo.name`, `workspace.git_worktree`, `workspace.current_dir`).
- Produces: a single-line powerline statusline. No later task depends on it.

- [ ] **Step 1: Back up the current statusline**

Run:
```bash
cp ~/.claude/statusline.sh ~/.claude/statusline.sh.bak && echo backed-up
```
Expected: `backed-up`.

- [ ] **Step 2: Write a verification that fails (still the old two-line output)**

Run:
```bash
printf '%s' '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"xhigh"},"workspace":{"repo":{"name":"claude-ghostty"},"current_dir":"'"$HOME"'"}}' \
  | ~/.claude/statusline.sh | cat -v | grep -c '48;2;217;161;117'
```
Expected: `0` (the old script doesn't emit the xhigh clay background `48;2;217;161;117`).

- [ ] **Step 3: Write the new statusline**

Overwrite `~/.claude/statusline.sh`:
```bash
#!/bin/bash
# Claude Code statusline: single powerline strip.
#   Segment 1 (effort-colored bg, near-black text): model display name.
#   Segment 2 (dark bg, light text):               repo + branch/worktree.
# Effort is conveyed by color only. bash 3.2 compatible.
input=$(cat)
[ -z "$input" ] && input='{}'   # jq's // fallback needs a parsed value; 0 bytes yields none

model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
effort=$(printf '%s' "$input" | jq -r '.effort.level // "none"' 2>/dev/null)
repo=$(printf '%s' "$input" | jq -r '.workspace.repo.name // empty' 2>/dev/null)
worktree=$(printf '%s' "$input" | jq -r '.workspace.git_worktree // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$model" ] && model="Claude"   # guard: malformed JSON leaves jq output empty

branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$repo" ] && [ -n "$cwd" ] && repo=$(basename "$cwd")

if [ -n "$worktree" ]; then
  loc="$repo wt:$worktree"
elif [ -n "$branch" ]; then
  loc="$repo on $branch"
else
  loc="$repo"
fi

case "$effort" in
  low)    eff_hex="8AA9C9" ;;
  medium) eff_hex="8FBAA0" ;;
  high)   eff_hex="D6C486" ;;
  xhigh)  eff_hex="D9A175" ;;
  max)    eff_hex="CC8385" ;;
  *)      eff_hex="8A93A0" ;;
esac

hex_rgb() { printf '%d;%d;%d' "$((16#${1:0:2}))" "$((16#${1:2:2}))" "$((16#${1:4:2}))"; }
eff_rgb=$(hex_rgb "$eff_hex")
seg2_bg="35;40;51"      # #232833
seg2_fg="174;183;196"   # #aeb7c4
ink="11;12;16"          # #0b0c10
sep=$(printf '\356\202\260')   # U+E0B0 powerline right triangle (octal for bash 3.2)

# segment 1: model on effort color
printf '\033[48;2;%sm\033[38;2;%sm %s ' "$eff_rgb" "$ink" "$model"
# separator seg1 -> seg2
printf '\033[38;2;%sm\033[48;2;%sm%s' "$eff_rgb" "$seg2_bg" "$sep"
# segment 2: location on dark
printf '\033[48;2;%sm\033[38;2;%sm %s ' "$seg2_bg" "$seg2_fg" "$loc"
# closing separator seg2 -> terminal bg
printf '\033[0m\033[38;2;%sm%s\033[0m' "$seg2_bg" "$sep"
```

- [ ] **Step 4: Run the failing verification again — now it passes**

Run:
```bash
printf '%s' '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"xhigh"},"workspace":{"repo":{"name":"claude-ghostty"},"current_dir":"'"$HOME"'"}}' \
  | ~/.claude/statusline.sh | cat -v | grep -c '48;2;217;161;117'
```
Expected: `1` (xhigh clay background present).

- [ ] **Step 5: Verify each effort maps to its color**

Run (grabs the **first** background code = the effort segment; `.*` greedy sed would wrongly grab segment 2, so use `grep -o | head -1`):
```bash
for e in low medium high xhigh max; do
  bg=$(printf '%s' '{"model":{"display_name":"M"},"effort":{"level":"'"$e"'"},"workspace":{"repo":{"name":"r"},"current_dir":"'"$HOME"'"}}' \
    | ~/.claude/statusline.sh | cat -v | grep -o '48;2;[0-9;]*m' | head -1)
  echo "$e=$bg"
done
```
Expected, one line per effort with these backgrounds:
`low=48;2;138;169;201m` · `medium=48;2;143;186;160m` · `high=48;2;214;196;134m` · `xhigh=48;2;217;161;117m` · `max=48;2;204;131;133m`.

- [ ] **Step 6: Verify worktree and no-effort fallbacks**

Run:
```bash
# worktree label (perl strips ANSI portably; BSD sed lacks \x escapes)
printf '%s' '{"model":{"display_name":"Sonnet 5"},"effort":{"level":"high"},"workspace":{"repo":{"name":"superpowers"},"git_worktree":"fix-hooks","current_dir":"'"$HOME"'"}}' \
  | ~/.claude/statusline.sh | perl -pe 's/\e\[[0-9;]*m//g'; echo
# absent effort -> muted slate 138;147;160
printf '%s' '{"model":{"display_name":"M"},"workspace":{"repo":{"name":"r"},"current_dir":"'"$HOME"'"}}' \
  | ~/.claude/statusline.sh | cat -v | grep -c '48;2;138;147;160'
```
Expected: first line contains `Sonnet 5 ` then ` superpowers wt:fix-hooks `; second command prints `1`.

- [ ] **Step 7: Confirm single-line output**

Run:
```bash
printf '%s' '{"model":{"display_name":"M"},"effort":{"level":"low"},"workspace":{"repo":{"name":"r"},"current_dir":"'"$HOME"'"}}' \
  | ~/.claude/statusline.sh | wc -l
```
Expected: `0` (no trailing newline → one visual line; Claude Code renders it as a single statusline row).

- [ ] **Step 8: Checkpoint**

Statusline rewrite done; rollback available via `mv ~/.claude/statusline.sh.bak ~/.claude/statusline.sh`.

---

### Task 5: Live end-to-end verification

**Files:** none (manual verification in real sessions).

- [ ] **Step 1: Reload the statusline in a real Ghostty split**

In an existing Claude Code session, the statusline refreshes on the next render. Confirm you see one powerline line: `[ <model> ][ <repo> on <branch> ]`, the left segment tinted by the current effort, powerline chevrons drawn crisply (Ghostty renders `U+E0B0` natively — no Nerd Font needed).

- [ ] **Step 2: Change effort live and watch the color follow**

Run in-session: `/effort low`, then `/effort max`. Expected: segment-1 background shifts dusty-blue → dusty-rose within a render tick, confirming `effort.level` is read live.

- [ ] **Step 3: Verify the menu bar across sessions**

With several splits open, confirm the menu-bar rings show the correct session/week remaining. Quit every Claude session and wait one refresh (or `open swiftbar://refreshallplugins`); confirm the item degrades gracefully to `⏱ –` if `claude-statusbar` reports no data, then recovers when a session resumes.

- [ ] **Step 4: Final checkpoint**

Both pieces live. Vertical space reclaimed: one line per split. Rollback notes are in the spec (`docs/superpowers/specs/2026-07-13-claude-status-cockpit-design.md`).
