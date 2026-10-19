#!/bin/bash
# llama-server: MistralRP-Noromaid 7B (Q5_K_M, 4.78 GiB) - fully in VRAM.
#
# Measured on GTX 1060 Mobile 6GB: pp512 338 t/s, tg128 22.4 t/s.
# A 7B at Q5 fits ENTIRELY in 6 GB VRAM, so decoding is GPU-bandwidth-bound
# instead of DDR4-bound: ~10x faster than a 27B with partial offload.
#
# OpenAI-compatible API + web UI on http://127.0.0.1:8080
# NOTE: stop any other llama-server first:  pkill -x llama-server
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}

exec "$HOME/llama.cpp/build/bin/llama-server" \
    -m "$HOME/models/MistralRP-Noromaid-NSFW-7B-Q5_K_M.gguf" \
    --alias mistralrp-7b \
    -ngl 99 \
    -c 4096 \
    -np 1 \
    -fa on \
    -ctk q8_0 -ctv q8_0 \
    --host 127.0.0.1 \
    --port 8080
