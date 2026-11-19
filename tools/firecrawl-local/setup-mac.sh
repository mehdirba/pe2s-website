#!/usr/bin/env bash
# Idempotent setup of firecrawl-local + fc wrapper + Claude Code skill on Apple Silicon macOS.
# Usage: ./setup-mac.sh            (CLI + Claude Code integration; recommended)
#        ./setup-mac.sh --desktop  (also add the MCP server to Claude Desktop, toggleable)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }; warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }; step(){ printf '\n\033[1m%s\033[0m\n' "$*"; }
DESKTOP=0; [ "${1:-}" = "--desktop" ] && DESKTOP=1
[ "$(uname -s)" = Darwin ] || { echo "macOS only"; exit 1; }
[ "$(uname -m)" = arm64 ] || warn "not arm64 ($(uname -m)); continuing"

step "1. Prerequisites"
if xcode-select -p >/dev/null 2>&1; then ok "Xcode CLT: $(xcode-select -p)"
else warn "Xcode CLT missing — opening installer. Re-run this script when it finishes."; xcode-select --install || true; exit 1; fi

BREW=""; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
[ -n "$BREW" ] && ok "Homebrew: $BREW" || warn "Homebrew missing (needed only to auto-install Node/Chrome): /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if command -v cargo >/dev/null; then ok "Rust: $(cargo --version)"
else
  warn "Rust missing — installing via rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  . "$HOME/.cargo/env"; ok "Rust: $(cargo --version)"
fi

nodev=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
if [ "$nodev" -ge 22 ]; then ok "Node: $(node --version)"
elif [ -n "$BREW" ]; then warn "Node ${nodev:-none} < 22 — installing"; "$BREW" install node; ok "Node: $(node --version)"
else warn "Node 22+ missing (only needed for the MCP server)"; fi

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
         "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
         "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
  [ -x "$c" ] && CHROME="$c" && break
done
if [ -z "$CHROME" ] && [ -n "$BREW" ]; then
  warn "No Chromium-family browser — installing Google Chrome (signed; brew's chromium cask fails Gatekeeper)"
  "$BREW" install --cask google-chrome
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi
[ -n "$CHROME" ] && ok "Browser: $CHROME" || warn "No Chrome: static pages work, JS pages return a warning"

step "2. firecrawl-local"
if command -v firecrawl-local >/dev/null && [ "${FORCE:-0}" != 1 ]; then ok "already installed: $(firecrawl-local --version) (FORCE=1 to reinstall)"
else cargo install firecrawl-local --locked; fi
FCL="$(command -v firecrawl-local)"; ok "binary: $FCL"

step "3. fc wrapper + config"
mkdir -p "$HOME/.local/bin" "$HOME/.config/fc"
install -m 755 "$HERE/fc" "$HOME/.local/bin/fc"
install -m 755 "$HERE/fc-desktop" "$HOME/.local/bin/fc-desktop"
if [ ! -f "$HOME/.config/fc/config" ]; then
  cat > "$HOME/.config/fc/config" <<EOF
# fc defaults — sourced by ~/.local/bin/fc
FCL_BIN="$FCL"
FIRECRAWL_LOCAL_BROWSER=auto   # static first, Chrome only for JS shells
FIRECRAWL_CLOUD=auto           # auto | search | off  (off = nothing leaves this Mac)
FC_MAX=12000                   # output cap in chars (~3k tokens)
FC_TTL_MIN=1440                # cache lifetime
EOF
  # Only pin the browser path when it is not one firecrawl-local auto-detects
  case "$CHROME" in "$HOME"/*) echo "FIRECRAWL_CHROME_PATH=\"$CHROME\"" >> "$HOME/.config/fc/config";; esac
fi
ok "~/.local/bin/fc, ~/.local/bin/fc-desktop, ~/.config/fc/config"
for rc in "$HOME/.zshrc"; do
  grep -q '.local/bin' "$rc" 2>/dev/null || { echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$rc"; ok "PATH added to $rc"; }
done
export PATH="$HOME/.local/bin:$PATH"

step "4. Claude Code integration (skill + CLAUDE.md rule + permission)"
mkdir -p "$HOME/.claude/skills/fc"
install -m 644 "$HERE/SKILL.md" "$HOME/.claude/skills/fc/SKILL.md"; ok "skill: ~/.claude/skills/fc/SKILL.md"
touch "$HOME/.claude/CLAUDE.md"
if ! grep -q 'fc:begin' "$HOME/.claude/CLAUDE.md"; then printf '\n' >> "$HOME/.claude/CLAUDE.md"; cat "$HERE/CLAUDE.md.snippet" >> "$HOME/.claude/CLAUDE.md"; fi
ok "rule: ~/.claude/CLAUDE.md"
/usr/bin/python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) and open(p).read().strip() else {}
if os.path.exists(p): shutil.copy2(p, p + ".bak-fc")
allow = d.setdefault("permissions", {}).setdefault("allow", [])
for r in ("Bash(fc:*)",):
    if r not in allow: allow.append(r)
json.dump(d, open(p, "w"), indent=2)
PY
ok "permission: Bash(fc:*) in ~/.claude/settings.json (no prompt per scrape)"

if [ "$DESKTOP" = 1 ]; then
  step "5. Claude Desktop MCP (toggleable)"
  "$HOME/.local/bin/fc-desktop" on
  ok "toggle with: fc-desktop off|on|status [--restart]"
fi

step "Smoke test"
fc -t https://www.rfc-editor.org/rfc/rfc8200 | head -8
echo; echo "Done. Open a new terminal (or: source ~/.zshrc). Do NOT run 'firecrawl-local init' — it registers the MCP server in every agent it finds."
