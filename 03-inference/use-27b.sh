#!/bin/bash
# Switch the GPU to the Qwen3.8-27B (quality tier, ~2 tok/s).
# Conflicts= automatically stops llama-server and comfyui.
# Back to the fast model:  sudo systemctl start llama-server
# Run with:  sudo bash ~/nvidia-gpu-install/use-27b.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

U="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$U" | cut -d: -f6)
F=/etc/systemd/system/llama-27b.service

if [ ! -f "$F" ]; then
    cat > "$F" <<EOF
[Unit]
Description=llama.cpp server (Qwen3.8-27B, GPU, quality tier)
After=network.target
Conflicts=llama-server.service comfyui.service

[Service]
User=$U
Environment=LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64
ExecStart=$REAL_HOME/llama.cpp/build/bin/llama-server -m /mnt/ai-store/models/Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf --alias qwen3.8-27b -ngl 20 -c 4096 -np 1 -fa on --stop "<|im_end|>" --stop "<|im_start|>" --host 127.0.0.1 --port 8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi

systemctl start llama-27b
sleep 3
echo "llama-27b: $(systemctl is-active llama-27b)"
echo "(the model takes ~1-2 min to page in from the Seagate)"
echo "Back to the fast 7B:  sudo systemctl start llama-server"
