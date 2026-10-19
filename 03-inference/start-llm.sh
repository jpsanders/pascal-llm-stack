#!/bin/bash
# llama-server: Qwen3.8-27B (UD-Q4_K_XL, 16.2 GiB) with partial GPU offload.
#
# Measured on GTX 1060 Mobile 6GB / 12 cores: pp256 ~70 t/s, tg ~2 t/s.
# Decode is limited by DDR4 bandwidth: only ~20 of 64 layers fit in 6 GB
# VRAM (24 layers needs 6360 MiB -> OOM), so ~70% of weights stream from
# system RAM each token. Quality-first config.
#
# OpenAI-compatible API + web UI on http://<host>:8080
# Bound to 0.0.0.0 so other Tailscale nodes can reach it directly; on the
# tailnet, access is governed by your Tailscale ACL (allow tcp/8080).
# NOTE: 0.0.0.0 also listens on LAN interfaces - if that bothers you, bind
# to the tailscale IP instead: --host $(tailscale ip -4)
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}

exec "$HOME/llama.cpp/build/bin/llama-server" \
    -m "$HOME/models/Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf" \
    --alias qwen3.8-27b \
    -ngl 20 \
    -c 4096 \
    -np 1 \
    --host 0.0.0.0 \
    --port 8080
