#!/usr/bin/env fish
# setup.fish — one-shot install for the local-model dev stack.
# Idempotent. Run from the repo root: ./scripts/setup.fish [--pull] [--portless]
#
#   (no flags)   install fish functions + OpenCode config + create derived models
#                from already-pulled bases (skips missing ones with a warning)
#   --pull       also pull base models first (~16 GB total: qwen3.5:9b 6.6G,
#                qwen3.5:4b 3.4G, gemma4:e4b-it-qat 6.1G)
#   --portless   also npm install -g portless

set -l repo (cd (dirname (status filename))/.. && pwd)
set -l pull 0
set -l portless 0
for a in $argv
    switch $a
        case --pull
            set pull 1
        case --portless
            set portless 1
        case '*'
            echo "unknown flag: $a" >&2
            exit 1
    end
end

# --- 0. preflight -----------------------------------------------------------
if not command -q ollama
    echo "ollama not found — brew install ollama" >&2
    exit 1
end
set -l over (ollama --version | string match -r '[0-9]+\.[0-9]+' )
echo "ollama $over detected (need >= 0.14 for the Anthropic-compatible API)"

if not curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null
    echo "warning: Ollama server not running on :11434 — start it, then re-run to create models" >&2
end

# --- 1. base models ---------------------------------------------------------
set -l bases qwen3.5:9b qwen3.5:4b gemma4:e4b-it-qat
if test $pull -eq 1
    for b in $bases
        echo "pulling $b ..."
        ollama pull $b
    end
end

# --- 2. derived models (num_ctx baked in) ------------------------------------
# Last two are optional bigger-RAM tiers — created only if you've pulled the base.
for pair in "qwen3.5-dev qwen3.5:9b" "qwen3.5-fast qwen3.5:4b" "gemma4-vision gemma4:e4b-it-qat" "qwen3.5-dev-27b qwen3.5:27b" "qwen3.5-dev-35b qwen3.5:35b-a3b"
    set -l name (string split ' ' $pair)[1]
    set -l base (string split ' ' $pair)[2]
    if ollama show $base >/dev/null 2>&1
        echo "creating $name (from $base)"
        ollama create $name -f $repo/models/$name.Modelfile
    else
        echo "skip $name: base $base not pulled (re-run with --pull)" >&2
    end
end

# --- 3. fish functions --------------------------------------------------------
set -l fdir ~/.config/fish/functions
mkdir -p $fdir
for f in $repo/fish/functions/*.fish
    set -l dest $fdir/(basename $f)
    if test -e $dest; and not test -L $dest
        echo "backing up existing $dest -> $dest.bak"
        mv $dest $dest.bak
    end
    ln -sf $f $dest
    echo "linked "(basename $f)
end

# --- 3a. slim system prompt (used by cc-turbo) ---------------------------------
mkdir -p ~/.config/local-llm-dev
cp $repo/templates/system-prompt.slim.md ~/.config/local-llm-dev/system-prompt.slim.md
cp $repo/config/mcp-local.json ~/.config/local-llm-dev/mcp-local.json
echo "installed ~/.config/local-llm-dev/{system-prompt.slim.md,mcp-local.json}"

# --- 3b. repomap on PATH (needed by the SessionStart hook + git hooks) --------
mkdir -p ~/.local/bin
ln -sf $repo/scripts/repomap.sh ~/.local/bin/repomap
ln -sf $repo/bin/cc-mcp ~/.local/bin/cc-mcp
ln -sf $repo/bin/cc-skill ~/.local/bin/cc-skill
echo "linked ~/.local/bin/{repomap,cc-mcp,cc-skill}"
if not contains ~/.local/bin $PATH
    echo "  note: add ~/.local/bin to PATH if it isn't already"
end

# --- 4. OpenCode config -------------------------------------------------------
set -l ocdir ~/.config/opencode
mkdir -p $ocdir
if test -e $ocdir/opencode.json
    cp $repo/config/opencode.json $ocdir/opencode.local-models.json
    echo "existing OpenCode config found — wrote $ocdir/opencode.local-models.json"
    echo "  merge the 'provider.ollama', 'model', and 'small_model' keys into your opencode.json manually"
else
    cp $repo/config/opencode.json $ocdir/opencode.json
    echo "installed $ocdir/opencode.json"
end

# --- 5. Ollama server tuning (menu-bar app) -----------------------------------
# If you run the Ollama.app instead of `ollama-tuned`, give the app the same env:
launchctl setenv OLLAMA_FLASH_ATTENTION 1
launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0
launchctl setenv OLLAMA_MAX_LOADED_MODELS 1
launchctl setenv OLLAMA_NUM_PARALLEL 1
echo "launchctl env set (takes effect after restarting the Ollama app)"

# --- 6. portless --------------------------------------------------------------
if test $portless -eq 1
    if command -q portless
        echo "portless already installed: "(command -v portless)
    else
        npm install -g portless
        echo "portless installed — run 'portless trust' once to set up local HTTPS"
    end
end

echo
echo "done. try:  cc-qwen        # Claude Code on qwen3.5-dev"
echo "            cc-gemma       # Claude Code on gemma4 (paste UI screenshots)"
echo "            oc-local       # OpenCode on qwen3.5-dev"
echo "per-project setup: see templates/AGENTS.local.md + scripts/repomap.sh"
