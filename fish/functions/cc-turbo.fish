function cc-turbo --description "Claude Code, local model + slim system prompt (max prefill speed)"
    # Replaces the ~10k-token harness prompt with ~200 tokens (templates/system-prompt.slim.md,
    # installed by setup.fish). Fastest option for 9b/4b models. Trade-off: no built-in
    # harness contract — the slim prompt re-teaches the essentials and defers to AGENTS.md.
    set -l prompt_file ~/.config/local-llm-dev/system-prompt.slim.md
    if not test -f $prompt_file
        echo "cc-turbo: $prompt_file missing — run scripts/setup.fish" >&2
        return 1
    end
    set -l model qwen3.5-dev
    if test (count $argv) -ge 1; and not string match -q -- '-*' $argv[1]
        set model $argv[1]
        set -e argv[1]
    end
    cc-local $model --system-prompt-file $prompt_file $argv
end
