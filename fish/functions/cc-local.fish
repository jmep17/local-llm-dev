function cc-local --description "Claude Code against local Ollama (Anthropic-compatible API, Ollama >= 0.14)"
    # Usage: cc-local [model] [claude args...]
    # First arg is treated as the model unless it starts with '-'.
    set -l model qwen3.5-dev
    if test (count $argv) -ge 1; and not string match -q -- '-*' $argv[1]
        set model $argv[1]
        set -e argv[1]
    end

    if not curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null
        echo "cc-local: Ollama not reachable on :11434 — run 'ollama serve' (or ollama-tuned) first" >&2
        return 1
    end

    # MCP allowlist: only context7 (docs lookup) + repomix run in local mode — no other
    # MCP servers get your code. --strict-mcp-config ignores all other MCP configs.
    set -l mcp_flags
    if test -f ~/.config/local-llm-dev/mcp-local.json
        set mcp_flags --strict-mcp-config --mcp-config ~/.config/local-llm-dev/mcp-local.json
    end

    # Tier mapping: opus/sonnet -> chosen model, haiku (background/fast tasks) -> qwen3.5-fast.
    # Overhead overrides (see README → 'Overhead overrides'):
    #   ATTRIBUTION_HEADER=0        per-request header line in system prompt kills KV cache (~90% slower prefill)
    #   DISABLE_NON_ESSENTIAL...=1  background haiku calls (titles/tips) queue behind the main model and stall it
    #   API_TIMEOUT_MS              local prefill is slow; timeouts trigger retries = double prefill
    env ANTHROPIC_BASE_URL=http://localhost:11434 \
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
        claude --model $model --exclude-dynamic-system-prompt-sections $mcp_flags $argv
    # --exclude-dynamic-system-prompt-sections: moves per-request bits (cwd, git status,
    # env info) out of the system prompt -> byte-stable prefix -> KV cache hit every turn.
    # Harmlessly ignored when cc-turbo adds --system-prompt-file.
end
