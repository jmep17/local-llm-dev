#!/usr/bin/env bash
# setup.sh — installer for bash/zsh machines (work PC). Fish users: scripts/setup.fish.
# Idempotent. Run from anywhere: ./scripts/setup.sh [--no-pull] [--portless]
#
#   (no flags)   full install: pull missing base models (~16 GB first time),
#                create derived models, link CLIs, install configs
#   --no-pull    skip downloads (wrappers auto-pull on first use anyway)
#   --portless   also npm install -g portless
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
PULL=1
PORTLESS=0
for a in "$@"; do
  case "$a" in
    --pull) PULL=1 ;;      # default now; kept for compatibility
    --no-pull) PULL=0 ;;
    --portless) PORTLESS=1 ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

# --- 0. preflight -------------------------------------------------------------
command -v ollama >/dev/null 2>&1 || { echo "ollama not found — install it first" >&2; exit 1; }
echo "ollama $(ollama --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) detected (need >= 0.14)"
if ! curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null 2>&1; then
  echo "warning: Ollama server not running on :11434 — start it, then re-run to create models" >&2
fi

# --- 1. base models -------------------------------------------------------------
BASES="qwen3.5:9b qwen3.5:4b gemma4:e4b-it-qat"
if [ "$PULL" -eq 1 ]; then
  for b in $BASES; do
    if ollama show "$b" >/dev/null 2>&1; then
      echo "$b already present"
    else
      echo "pulling $b ..."
      ollama pull "$b"
    fi
  done
fi

# --- 2. derived models (num_ctx baked in; optional tiers skip if base absent) ---
while read -r name base; do
  if ollama show "$base" >/dev/null 2>&1; then
    echo "creating $name (from $base)"
    ollama create "$name" -f "$REPO/models/$name.Modelfile"
  else
    echo "skip $name: base $base not pulled" >&2
  fi
done <<'EOF'
qwen3.5-dev qwen3.5:9b
qwen3.5-fast qwen3.5:4b
gemma4-vision gemma4:e4b-it-qat
qwen3.5-dev-27b qwen3.5:27b
qwen3.5-dev-35b qwen3.5:35b-a3b
EOF

# --- 3. shared config: slim prompt + MCP allowlist ------------------------------
mkdir -p "$CFG/local-llm-dev"
cp "$REPO/templates/system-prompt.slim.md" "$CFG/local-llm-dev/system-prompt.slim.md"
cp "$REPO/config/mcp-local.json" "$CFG/local-llm-dev/mcp-local.json"
echo "installed $CFG/local-llm-dev/{system-prompt.slim.md,mcp-local.json}"

# --- 4. repomap on PATH ----------------------------------------------------------
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO/scripts/repomap.sh" "$HOME/.local/bin/repomap"
ln -sf "$REPO/bin/cc-mcp" "$HOME/.local/bin/cc-mcp"
ln -sf "$REPO/bin/cc-skill" "$HOME/.local/bin/cc-skill"
ln -sf "$REPO/bin/cc-ensure-model" "$HOME/.local/bin/cc-ensure-model"
echo "linked ~/.local/bin/{repomap,cc-mcp,cc-skill,cc-ensure-model}"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "  note: add ~/.local/bin to PATH" ;;
esac

# --- 5. shell functions -----------------------------------------------------------
SRC_LINE="source $REPO/shell/local-llm-dev.zsh"
if [ -f "$HOME/.zshrc" ] && grep -qF "local-llm-dev.zsh" "$HOME/.zshrc"; then
  echo "zsh functions already sourced in ~/.zshrc"
else
  echo
  echo "add this line to ~/.zshrc, then open a new shell:"
  echo "  $SRC_LINE"
fi

# --- 6. OpenCode config -------------------------------------------------------------
mkdir -p "$CFG/opencode"
if [ -e "$CFG/opencode/opencode.json" ]; then
  cp "$REPO/config/opencode.json" "$CFG/opencode/opencode.local-models.json"
  echo "existing OpenCode config found — wrote opencode.local-models.json; merge manually"
else
  cp "$REPO/config/opencode.json" "$CFG/opencode/opencode.json"
  echo "installed $CFG/opencode/opencode.json"
fi

# --- 7. Ollama server tuning (macOS menu-bar app only) -------------------------------
if [ "$(uname)" = "Darwin" ]; then
  launchctl setenv OLLAMA_FLASH_ATTENTION 1
  launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0
  launchctl setenv OLLAMA_MAX_LOADED_MODELS 1
  launchctl setenv OLLAMA_NUM_PARALLEL 1
  echo "launchctl env set (restart the Ollama app to apply)"
else
  echo "Linux: set OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=1 in the ollama service env (or use ollama-tuned)"
fi

# --- 8. portless ----------------------------------------------------------------------
if [ "$PORTLESS" -eq 1 ]; then
  if command -v portless >/dev/null 2>&1; then
    echo "portless already installed: $(command -v portless)"
  else
    npm install -g portless
    echo "portless installed — run 'portless trust' once for local HTTPS"
  fi
fi

echo
echo "done. new shell, then:  cc-qwen | cc-turbo | cc-gemma | oc-local | cc-mode local"
