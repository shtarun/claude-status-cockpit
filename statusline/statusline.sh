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

# Feed the menu-bar rings: cache the stdin JSON (only when it carries rate
# limits), stamped with the logged-in account so the SwiftBar plugin can
# invalidate on account switch. Atomic mv: parallel sessions write this too.
if printf '%s' "$input" | jq -e '.rate_limits.five_hour' >/dev/null 2>&1; then
  cache_dir="$HOME/.cache/claude-statusbar"
  mkdir -p "$cache_dir"
  acct=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
  tmp=$(mktemp "$cache_dir/.stdin.XXXXXX" 2>/dev/null)
  if [ -n "$tmp" ]; then
    if printf '%s' "$input" | jq --arg acct "$acct" '. + {_account: $acct}' > "$tmp" 2>/dev/null; then
      mv -f "$tmp" "$cache_dir/last_stdin.json"
    else
      rm -f "$tmp"
    fi
  fi
fi

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
