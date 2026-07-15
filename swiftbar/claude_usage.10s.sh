#!/bin/bash
# <xbar.title>Claude Usage</xbar.title>
# <xbar.desc>Session (5h) + week (7d) USED % as twin ring gauges, live from the statusline cache.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:$PATH"

DIR="$HOME/Library/Application Support/SwiftBar"
RENDERER="$DIR/render_rings.swift"   # kept OUT of plugins/ so SwiftBar doesn't run it as a plugin
CACHE="$DIR/cache"
STDIN_CACHE="$HOME/.cache/claude-statusbar/last_stdin.json"
mkdir -p "$CACHE"
find "$CACHE" -name 'rings_*.png' -mtime +1 -delete 2>/dev/null

GREY="#8A93A0"
cur_acct="$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)"

unavailable() {
  echo "⏱ – | color=$GREY font=Menlo size=13"
  echo "---"
  echo "$1"
  echo "Refresh | refresh=true"
  exit 0
}

[ -r "$STDIN_CACHE" ] || unavailable "Claude usage unavailable (no session has reported yet)"

json="$(cat "$STDIN_CACHE" 2>/dev/null)"
s_used="$(printf '%s' "$json" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | floor' 2>/dev/null)"
w_used="$(printf '%s' "$json" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | floor' 2>/dev/null)"
s_at="$(printf '%s' "$json" | jq -r '.rate_limits.five_hour.resets_at // 0' 2>/dev/null)"
w_at="$(printf '%s' "$json" | jq -r '.rate_limits.seven_day.resets_at // 0' 2>/dev/null)"
cache_acct="$(printf '%s' "$json" | jq -r '._account // empty' 2>/dev/null)"

[ -n "$s_used" ] && [ -n "$w_used" ] || unavailable "Claude usage unavailable (cache has no rate limits)"

# Account switch: cached numbers belong to a different login -> invalidate.
if [ -n "$cur_acct" ] && [ -n "$cache_acct" ] && [ "$cache_acct" != "$cur_acct" ]; then
  unavailable "Switched account — awaiting data for $cur_acct (start any Claude session)"
fi

now=$(date +%s)
age=$(( now - $(stat -f %m "$STDIN_CACHE" 2>/dev/null || echo "$now") ))
stale=""
[ "$age" -gt 600 ] && stale="stale"

# Countdown from a resets_at epoch; clamps at "now".
fmt_reset() {
  local left=$(( $1 - now ))
  if [ "$1" -le 0 ]; then echo "?"
  elif [ "$left" -le 0 ]; then echo "now"
  elif [ "$left" -ge 3600 ]; then echo "$(( left / 3600 ))h $(( (left % 3600) / 60 ))m"
  else echo "$(( left / 60 ))m"
  fi
}
s_reset="$(fmt_reset "$s_at")"
w_reset="$(fmt_reset "$w_at")"

# Compact single-unit countdown for the TITLE only. The menu bar item sits
# ~22pt right of the notch; a long "109h 21m" title widens it enough that any
# transient system icon pushes it into the notch and macOS hides it entirely.
fmt_reset_short() {
  local left=$(( $1 - now ))
  if [ "$1" -le 0 ]; then echo "?"
  elif [ "$left" -le 0 ]; then echo "now"
  elif [ "$left" -lt 3600 ]; then echo "$(( left / 60 ))m"
  elif [ "$left" -lt 172800 ]; then echo "$(( left / 3600 ))h"
  else echo "$(( left / 86400 ))d"
  fi
}

# Human-readable cache age for the dropdown.
if [ "$age" -lt 60 ]; then age_txt="${age}s ago"
elif [ "$age" -lt 3600 ]; then age_txt="$(( age / 60 ))m ago"
else age_txt="$(( age / 3600 ))h $(( (age % 3600) / 60 ))m ago"
fi

# Short countdowns drawn inside the image: session LEFT of the rings, week RIGHT.
s_short="$(fmt_reset_short "$s_at")"
w_short="$(fmt_reset_short "$w_at")"

# Ring image = percentages + short countdowns + staleness. Countdown churn is
# at most once a minute; old PNGs are pruned daily above.
img="$CACHE/rings_s${s_used}_w${w_used}_${s_short}_${w_short}${stale:+_stale}.png"
[ -f "$img" ] || swift "$RENDERER" "$s_used" "$w_used" "$s_short" "$w_short" "$img" $stale 2>/dev/null

if [ -f "$img" ]; then
  # Rings only — NO title text. The menu bar next to the notch has been
  # observed to tighten by 40+pt (Control Centre growth, new app icons);
  # at 89pt with title text this item got notch-evicted twice. ~50pt always
  # fits. The binding-limit countdown lives in the dropdown instead.
  b64="$(base64 < "$img" | tr -d '\n')"
  echo "| image=$b64"
else
  # Fallback: compact text-only line if the renderer is unavailable (kept
  # narrow for the same notch reason as the title).
  scol="#8FBAA0"; [ "$s_used" -ge 60 ] && scol="#D6C486"; [ "$s_used" -ge 85 ] && scol="#C4524F"
  [ -n "$stale" ] && scol="$GREY"
  echo "${s_short}·${s_used}·${w_used}%·${w_short} | color=$scol font=Menlo size=13"
fi

echo "---"
echo "Claude usage${cur_acct:+ — $cur_acct}"
echo "Session (5h)  ${s_used}% used · resets ${s_reset} | font=Menlo"
echo "Week (7d)     ${w_used}% used · resets ${w_reset} | font=Menlo"
echo "data as of ${age_txt}${stale:+ (stale)} | color=$GREY size=11"
echo "---"
echo "Refresh | refresh=true"
