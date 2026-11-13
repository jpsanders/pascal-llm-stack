#!/bin/bash
# Install systemd services for the AI stack. Benefits:
#  - services survive SSH/session restarts and machine reboots
#  - GPU handoff: starting one workload stops the other (Conflicts=)
#      sudo systemctl start llama-server   # text chat (stops comfyui)
#      sudo systemctl start comfyui        # image/video (stops llama-server)
#    llama-web (the :8080 proxy/UI) runs always and is GPU-independent.
# Run with:  sudo bash ~/nvidia-gpu-install/setup-services.sh
# Set MODEL to your 7B GGUF file (sudo MODEL=/path/to/model.gguf bash ...);
# the default path is only an example.
# ComfyUI listens on 127.0.0.1 and has no login. Reach it over the tailnet with
# `tailscale serve --bg --https=8443 http://127.0.0.1:8188`; COMFY_LISTEN=0.0.0.0 opens it to the whole LAN.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

# Resolve the REAL invoking user (sudo sets $HOME to /root)
U="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$U" | cut -d: -f6)
echo "installing services for user: $U (home: $REAL_HOME)"
ENV="LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64"
MODEL="${MODEL:-/mnt/ai-store/models/Mistral-7B-Q5_K_M.gguf}"

# Stop any session-spawned copies so the services own the ports/GPU
pkill -x llama-server 2>/dev/null || true
pkill -f "[l]lama-proxy.py" 2>/dev/null || true
pkill -f "[C]omfyUI/main.py" 2>/dev/null || true
sleep 2

cat > /etc/systemd/system/llama-server.service <<EOF
[Unit]
Description=llama.cpp server (Mistral 7B, GPU)
After=network.target
Conflicts=comfyui.service

[Service]
User=$U
Environment=$ENV
ExecStart=$REAL_HOME/llama.cpp/build/bin/llama-server -m $MODEL --alias mistral-7b -ngl 99 -c 4096 -np 1 -fa on -ctk q8_0 -ctv q8_0 -r "<|im_end|>" -r "<|im_start|>" --host 127.0.0.1 --port 8090
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
WorkingDirectory=$REAL_HOME/ComfyUI
ExecStart=$REAL_HOME/comfy-venv/bin/python main.py --listen ${COMFY_LISTEN:-127.0.0.1} --port 8188 --output-directory /mnt/ai-store/comfy/output --fp32-vae --cache-ram 6
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
ExecStart=/usr/bin/python3 $REAL_HOME/nvidia-gpu-install/llama-proxy.py
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
