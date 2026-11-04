#!/bin/bash
# Launch llama-server with a Qwen3.8 27B model (UD-Q4_K_XL).
# Set MODEL to your GGUF file; the default path is only an example.
# GTX 1060 6GB: 20 of 64 layers on GPU, rest in system RAM (~2 t/s gen, ~70 t/s prompt).
# OpenAI-compatible API + web UI at http://127.0.0.1:8080
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
MODEL="${MODEL:-/mnt/ai-store/models/Qwen3.8-27B-UD-Q4_K_XL.gguf}"

exec ~/llama.cpp/build/bin/llama-server \
    -m "$MODEL" \
    --alias qwen3.8-27b \
    -ngl 20 \
    -c 4096 \
    -np 1 \
    -fa on \
    \
    \
    --host 127.0.0.1 \
    --port 8090
