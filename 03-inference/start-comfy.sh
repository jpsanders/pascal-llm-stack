#!/bin/bash
# ComfyUI UI on 0.0.0.0:8188 (tailnet-reachable like the LLM stack).
# Models load from /mnt/ai-store/comfy via extra_model_paths.yaml.
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
exec ~/comfy-venv/bin/python ~/ComfyUI/main.py --listen 0.0.0.0 --port 8188
