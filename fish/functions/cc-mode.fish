function cc-mode --description "Toggle plain 'claude' between cloud and local Ollama for this shell session"
    # cc-mode local [model]  -> exports Ollama env; plain `claude` hits local models
    # cc-mode cloud          -> erases the overrides; plain `claude` uses your normal settings/login
    # cc-mode status         -> show current mode
    #
    # Session-scoped only: new terminals always start in cloud mode. Your
    # ~/.claude/settings.json is never touched.
    switch "$argv[1]"
        case local
            set -l model qwen3.5-dev
            if test (count $argv) -ge 2
                set model $argv[2]
            end
            if not curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null
                echo "cc-mode: Ollama not reachable on :11434 — start it first" >&2
                return 1
            end
            set -gx ANTHROPIC_BASE_URL http://localhost:11434
            set -gx ANTHROPIC_AUTH_TOKEN ollama
            set -gx ANTHROPIC_API_KEY ""
            set -gx ANTHROPIC_MODEL $model
            set -gx ANTHROPIC_DEFAULT_OPUS_MODEL $model
            set -gx ANTHROPIC_DEFAULT_SONNET_MODEL $model
            set -gx ANTHROPIC_DEFAULT_HAIKU_MODEL qwen3.5-fast
            set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0
            set -gx DISABLE_NON_ESSENTIAL_MODEL_CALLS 1
            set -gx CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
            set -gx CLAUDE_CODE_DISABLE_AGENT_VIEW 1
            set -gx API_TIMEOUT_MS 600000
            # Shadow `claude` so plain invocations also get the cache-stable prompt flag
            # (env vars can't carry CLI flags). Removed by 'cc-mode cloud'.
            function claude --wraps claude --description "claude (cc-mode local: cache-stable prompt, MCP allowlist)"
                set -l mcp_flags
                if test -f ~/.config/local-llm-dev/mcp-local.json
                    set mcp_flags --strict-mcp-config --mcp-config ~/.config/local-llm-dev/mcp-local.json
                end
                command claude --exclude-dynamic-system-prompt-sections $mcp_flags $argv
            end
            echo "claude → LOCAL ($model) in this shell. 'cc-mode cloud' to switch back."
        case cloud
            set -e ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_ATTRIBUTION_HEADER DISABLE_NON_ESSENTIAL_MODEL_CALLS CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_DISABLE_AGENT_VIEW API_TIMEOUT_MS
            functions -e claude 2>/dev/null
            echo "claude → CLOUD (your existing settings/login)."
            echo "note: if your own config exports ANTHROPIC_API_KEY, open a new shell to restore it."
        case status ''
            if set -q ANTHROPIC_BASE_URL
                echo "mode: LOCAL → $ANTHROPIC_BASE_URL (model: $ANTHROPIC_MODEL)"
            else
                echo "mode: CLOUD (default settings)"
            end
        case '*'
            echo "usage: cc-mode local [model] | cloud | status" >&2
            return 1
    end
end
