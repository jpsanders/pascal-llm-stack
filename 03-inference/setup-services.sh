#!/bin/bash
# Install systemd services for the AI stack. Benefits:
#  - services survive SSH/session restarts and machine reboots
#  - GPU handoff: starting one workload stops the other (Conflicts=)
#      sudo systemctl start llama-server   # text chat (stops comfyui)
#      sudo systemctl start comfyui        # image/video (stops llama-server)
#    llama-web (the :8080 proxy/UI) runs always and is GPU-independent.
# Run with:  sudo bash ~/nvidia-gpu-install/setup-services.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

U=james-sanders
ENV="LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64"

# Stop any session-spawned copies so the services own the ports/GPU
pkill -x llama-server 2>/dev/null || true
pkill -f "[l]lama-proxy.py" 2>/dev/null || true
pkill -f "[C]omfyUI/main.py" 2>/dev/null || true
sleep 2

cat > /etc/systemd/system/llama-server.service <<EOF
[Unit]
Description=llama.cpp server (MistralRP 7B, GPU)
After=network.target
Conflicts=comfyui.service

[Service]
User=$U
Environment=$ENV
ExecStart=$HOME/llama.cpp/build/bin/llama-server -m /mnt/ai-store/models/MistralRP-Noromaid-NSFW-7B-Q5_K_M.gguf --alias mistralrp-7b -ngl 99 -c 4096 -np 1 -fa on -ctk q8_0 -ctv q8_0 --mlock --cache-reuse 256 --host 127.0.0.1 --port 8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI (Qwen-Image / Wan2.2 on GPU)
After=network.target
Conflicts=llama-server.service

[Service]
User=$U
Environment=$ENV
WorkingDirectory=$HOME/ComfyUI
ExecStart=$HOME/comfy-venv/bin/python main.py --listen 0.0.0.0 --port 8188 --output-directory /mnt/ai-store/comfy/output --fp32-vae --cache-ram 6
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/llama-web.service <<EOF
[Unit]
Description=Proxy: web UI + API on :8080
After=network.target llama-server.service

[Service]
User=$U
ExecStart=/usr/bin/python3 $HOME/nvidia-gpu-install/llama-proxy.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now llama-web llama-server

echo "=== status ==="
systemctl is-active llama-web llama-server
echo
echo "GPU switch commands:"
echo "  text mode:  sudo systemctl start llama-server   (stops comfyui)"
echo "  media mode: sudo systemctl start comfyui        (stops llama-server)"
echo "  ComfyUI UI: http://usb-ubuntu:8188   LLM UI+API: http://usb-ubuntu:8080"
