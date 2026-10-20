#!/bin/bash
# Download all diffusion models to the Seagate store (sequential, resumable).
# Image: Qwen-Image 2.1 Turbo-Uncensored (DiT) + abliterated text encoder + VAE
# Video: Wan2.2 I2V A14B Q6_K experts + umt5 encoder + VAE + NSFW LoRA pair
set -uo pipefail
BASE=/mnt/ai-store/comfy
mkdir -p $BASE/{diffusion_models/wan2.2,text_encoders/wan2.2,vae/wan2.2,loras/wan2.2}

dl() { # url dest
    local url="$1" dest="$2"
    if [ -f "$dest" ] && [ -s "$dest" ]; then echo "SKIP $(basename $dest)"; return 0; fi
    echo "GET  $(basename $dest)"
    curl -sL --retry 20 --retry-all-errors --retry-delay 5 -C - -o "$dest" "$url" \
        && echo "OK   $(basename $dest)" || echo "FAIL $(basename $dest)"
}

HF=https://huggingface.co

dl "$HF/AtomicChat/Qwen-Image-2.1-Turbo-Uncensored-GGUF/resolve/main/Qwen-Image-2.1-Turbo-Uncensored-Q8_0.gguf" \
   "$BASE/diffusion_models/Qwen-Image-2.1-Turbo-Uncensored-Q8_0.gguf"

dl "$HF/NidAll/Qwen3VL-8B-Abliterated-INT8-ConvRot/resolve/main/qwen3vl_8b_abliterated_int8_convrot.safetensors" \
   "$BASE/text_encoders/qwen3vl_8b_abliterated_int8_convrot.safetensors"

dl "$HF/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors" \
   "$BASE/vae/qwen_image_2.1_vae_bf16.safetensors"

dl "$HF/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/main/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
   "$BASE/diffusion_models/wan2.2/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf"

dl "$HF/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/main/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
   "$BASE/diffusion_models/wan2.2/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf"

dl "$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
   "$BASE/text_encoders/wan2.2/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

dl "$HF/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/main/VAE/Wan2.1_VAE.safetensors" \
   "$BASE/vae/wan2.2/Wan2.1_VAE.safetensors"

dl "$HF/lopi999/Wan2.2-I2V_General-NSFW-LoRA/resolve/main/NSFW-22-H-e8.safetensors" \
   "$BASE/loras/wan2.2/NSFW-22-H-e8.safetensors"

dl "$HF/lopi999/Wan2.2-I2V_General-NSFW-LoRA/resolve/main/NSFW-22-L-e8.safetensors" \
   "$BASE/loras/wan2.2/NSFW-22-L-e8.safetensors"

echo "=== ALL DOWNLOADS DONE ==="
find $BASE -type f -name '*.gguf' -o -name '*.safetensors' | xargs ls -la | awk '{printf "%8.2f GB  %s\n", $5/1073741824, $9}'
