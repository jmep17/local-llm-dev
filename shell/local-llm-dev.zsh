# local-llm-dev.zsh — zsh port of the fish functions, for the work PC.
# Install: source this from ~/.zshrc:
#   source /path/to/local-llm-dev/shell/local-llm-dev.zsh
# (scripts/setup.sh prints the exact line.)

_LLMDEV_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/local-llm-dev"

_llmdev_ollama_up() {
  curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null 2>&1
}

_llmdev_mcp_flags() {
  # MCP allowlist: context7 + repomix only; ignore all other MCP configs.
  if [[ -f "$_LLMDEV_CFG/mcp-local.json" ]]; then
    print -r -- --strict-mcp-config --mcp-config "$_LLMDEV_CFG/mcp-local.json"
  fi
}

cc-local() {
  local model=qwen3.5-dev
  if [[ $# -gt 0 && $1 != -* ]]; then
    model=$1
    shift
  fi
  if ! _llmdev_ollama_up; then
    echo "cc-local: Ollama not reachable on :11434 — start it first" >&2
    return 1
  fi
  # Auto-pull/create the model if it doesn't exist yet (first use = big download).
  if command -v cc-ensure-model >/dev/null 2>&1; then
    cc-ensure-model $model || return 1
  fi
  local -a mcp
  mcp=(${(z)$(_llmdev_mcp_flags)})
  ANTHROPIC_BASE_URL=http://localhost:11434 \
  ANTHROPIC_AUTH_TOKEN=ollama \
  ANTHROPIC_API_KEY= \
  ANTHROPIC_DEFAULT_OPUS_MODEL=$model \
  ANTHROPIC_DEFAULT_SONNET_MODEL=$model \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.5-fast \
  CLAUDE_CODE_ATTRIBUTION_HEADER=0 \
  DISABLE_NON_ESSENTIAL_MODEL_CALLS=1 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  CLAUDE_CODE_DISABLE_AGENT_VIEW=1 \
  API_TIMEOUT_MS=600000 \
  command claude --model $model --exclude-dynamic-system-prompt-sections "${mcp[@]}" "$@"
}

cc-qwen()  { cc-local qwen3.5-dev "$@" }
cc-gemma() { cc-local gemma4-vision "$@" }

cc-turbo() {
  # Slim ~200-token system prompt instead of the ~10k harness prompt (max prefill speed).
  local prompt_file="$_LLMDEV_CFG/system-prompt.slim.md"
  if [[ ! -f $prompt_file ]]; then
    echo "cc-turbo: $prompt_file missing — run scripts/setup.sh" >&2
    return 1
  fi
  local model=qwen3.5-dev
  if [[ $# -gt 0 && $1 != -* ]]; then
    model=$1
    shift
  fi
  cc-local $model --system-prompt-file "$prompt_file" "$@"
}

oc-local() {
  local model=qwen3.5-dev
  if [[ $# -gt 0 && $1 != -* ]]; then
    model=$1
    shift
  fi
  command opencode --model ollama/$model "$@"
}

ollama-tuned() {
  # q8_0 KV cache + flash attention: makes 64k context viable. Quit any Ollama app first.
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_MAX_LOADED_MODELS=1 \
  OLLAMA_NUM_PARALLEL=1 \
  OLLAMA_KEEP_ALIVE=30m \
  command ollama serve
}

cc-mode() {
  # cc-mode local [model] | cloud | status — session-wide toggle for plain `claude`.
  # Env-only; your ~/.claude settings and login are never touched.
  case "$1" in
    local)
      local model=${2:-qwen3.5-dev}
      if ! _llmdev_ollama_up; then
        echo "cc-mode: Ollama not reachable on :11434 — start it first" >&2
        return 1
      fi
      if command -v cc-ensure-model >/dev/null 2>&1; then
        cc-ensure-model $model || return 1
      fi
      export ANTHROPIC_BASE_URL=http://localhost:11434
      export ANTHROPIC_AUTH_TOKEN=ollama
      export ANTHROPIC_API_KEY=""
      export ANTHROPIC_MODEL=$model
      export ANTHROPIC_DEFAULT_OPUS_MODEL=$model
      export ANTHROPIC_DEFAULT_SONNET_MODEL=$model
      export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.5-fast
      export CLAUDE_CODE_ATTRIBUTION_HEADER=0
      export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
      export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
      export CLAUDE_CODE_DISABLE_AGENT_VIEW=1
      export API_TIMEOUT_MS=600000
      # Shadow plain `claude` so it gets the CLI flags too (env can't carry flags).
      claude() {
        local -a mcp
        mcp=(${(z)$(_llmdev_mcp_flags)})
        command claude --exclude-dynamic-system-prompt-sections "${mcp[@]}" "$@"
      }
      echo "claude → LOCAL ($model) in this shell. 'cc-mode cloud' to switch back."
      ;;
    cloud)
      unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL \
            ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL \
            CLAUDE_CODE_ATTRIBUTION_HEADER DISABLE_NON_ESSENTIAL_MODEL_CALLS \
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_DISABLE_AGENT_VIEW API_TIMEOUT_MS
      unfunction claude 2>/dev/null
      echo "claude → CLOUD (your existing settings/login)."
      echo "note: if your own zshrc exports ANTHROPIC_API_KEY, open a new shell to restore it."
      ;;
    status|"")
      if [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
        echo "mode: LOCAL → $ANTHROPIC_BASE_URL (model: ${ANTHROPIC_MODEL:-?})"
      else
        echo "mode: CLOUD (default settings)"
      fi
      ;;
    *)
      echo "usage: cc-mode local [model] | cloud | status" >&2
      return 1
      ;;
  esac
}
