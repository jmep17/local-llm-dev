function ollama-tuned --description "Run Ollama server tuned for agent workloads on 16GB Apple Silicon"
    # q8_0 KV cache roughly halves KV memory -> makes 64k context viable for a 9B q4 model.
    # One loaded model + one parallel request: everything else swaps on 16 GB.
    # NOTE: quit the Ollama menu-bar app first, or this port is taken.
    OLLAMA_FLASH_ATTENTION=1 \
    OLLAMA_KV_CACHE_TYPE=q8_0 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_NUM_PARALLEL=1 \
    OLLAMA_KEEP_ALIVE=30m \
    ollama serve
end
