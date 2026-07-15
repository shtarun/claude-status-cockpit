#!/bin/bash
# Installer for claude-status-cockpit.
# Copies the statusline + SwiftBar plugin into place, wires Claude Code's
# statusLine setting, and points SwiftBar at the plugin directory.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar"
PLUGIN_DIR="$SWIFTBAR_DIR/plugins"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP="$(date +%Y%m%d_%H%M%S)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "macOS only (SwiftBar is a macOS app)."

bold "Checking dependencies…"
command -v jq >/dev/null || fail "jq is required:  brew install jq"
command -v swift >/dev/null || fail "swift is required (Xcode Command Line Tools):  xcode-select --install"
command -v claude >/dev/null || echo "  note: 'claude' CLI not found on PATH — install Claude Code first (https://claude.com/claude-code)"
if [ ! -d "/Applications/SwiftBar.app" ] && ! ls "$HOME/Applications/SwiftBar.app" >/dev/null 2>&1; then
  fail "SwiftBar is required:  brew install --cask swiftbar"
fi
echo "  ok"

bold "Installing statusline…"
mkdir -p "$CLAUDE_DIR"
if [ -f "$CLAUDE_DIR/statusline.sh" ]; then
  cp "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh.bak.$STAMP"
  echo "  existing statusline backed up to statusline.sh.bak.$STAMP"
fi
install -m 0755 "$REPO_DIR/statusline/statusline.sh" "$CLAUDE_DIR/statusline.sh"
echo "  installed $CLAUDE_DIR/statusline.sh"

bold "Wiring Claude Code statusLine setting…"
if [ -f "$SETTINGS" ]; then
  current="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)"
  if [ -z "$current" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$STAMP"
    jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh"}' "$SETTINGS" > "$SETTINGS.tmp" \
      && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "  statusLine added to settings.json (backup: settings.json.bak.$STAMP)"
  elif [ "$current" = "~/.claude/statusline.sh" ] || [ "$current" = "$CLAUDE_DIR/statusline.sh" ]; then
    echo "  statusLine already points at ~/.claude/statusline.sh"
  else
    echo "  NOTE: your statusLine currently runs: $current"
    echo "        left untouched — point it at ~/.claude/statusline.sh to feed the rings."
  fi
else
  printf '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}\n' | jq . > "$SETTINGS"
  echo "  created settings.json with statusLine"
fi

bold "Installing SwiftBar plugin…"
mkdir -p "$PLUGIN_DIR"
# Renderer lives OUTSIDE plugins/ so SwiftBar doesn't try to execute it as a plugin.
install -m 0644 "$REPO_DIR/swiftbar/render_rings.swift" "$SWIFTBAR_DIR/render_rings.swift"
install -m 0755 "$REPO_DIR/swiftbar/claude_usage.10s.sh" "$PLUGIN_DIR/claude_usage.10s.sh"
echo "  installed renderer + claude_usage.10s.sh"

configured_dir="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$configured_dir" ]; then
  defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"
  echo "  SwiftBar plugin directory set to $PLUGIN_DIR"
elif [ "$configured_dir" != "$PLUGIN_DIR" ]; then
  echo "  NOTE: SwiftBar already uses plugin dir: $configured_dir"
  cp "$REPO_DIR/swiftbar/claude_usage.10s.sh" "$configured_dir/claude_usage.10s.sh"
  chmod +x "$configured_dir/claude_usage.10s.sh"
  echo "        copied the plugin there too (renderer stays in $SWIFTBAR_DIR)."
fi

bold "Starting SwiftBar…"
open -a SwiftBar
sleep 2
open "swiftbar://refreshallplugins" 2>/dev/null || true

bold "Done."
echo "The rings appear after your next Claude Code interaction (any keystroke in a"
echo "session makes the statusline report usage, which feeds the menu bar)."
echo
echo "Rollback: restore $CLAUDE_DIR/statusline.sh.bak.$STAMP and delete"
echo "$PLUGIN_DIR/claude_usage.10s.sh"
