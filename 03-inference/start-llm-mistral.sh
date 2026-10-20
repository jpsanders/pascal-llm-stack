#!/bin/bash
# Launch llama-server with MistralRP-Noromaid 7B (Q5_K_M).
# 7B fits ENTIRELY in the 1060's 6GB VRAM -> fast (~15-25 t/s expected).
# OpenAI-compatible API + web UI at http://127.0.0.1:8080
# NOTE: stop the Qwen3.8 server first if it's running (same port).
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}

exec ~/llama.cpp/build/bin/llama-server \
    -m ~/models/MistralRP-Noromaid-NSFW-7B-Q5_K_M.gguf \
    --alias mistralrp-7b \
    -ngl 99 \
    -c 65536 --no-kv-offload --rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 32768 \
    -np 1 \
    -fa on \
    -ctk q8_0 -ctv q8_0 \
    --host 127.0.0.1 \
    --port 8090
