function oc-local --description "OpenCode on local Ollama (qwen3.5-dev by default)"
    # Usage: oc-local [model] [opencode args...]
    set -l model qwen3.5-dev
    if test (count $argv) -ge 1; and not string match -q -- '-*' $argv[1]
        set model $argv[1]
        set -e argv[1]
    end
    opencode --model ollama/$model $argv
end
