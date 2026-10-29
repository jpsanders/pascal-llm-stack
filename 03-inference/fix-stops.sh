#!/bin/bash
# Add stop tokens to the llama-server service (MistralRP kept generating a
# fake user turn past <|im_end|>) and restart it.
# Run with:  sudo bash ~/nvidia-gpu-install/fix-stops.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

F=/etc/systemd/system/llama-server.service
[ -f "$F" ] || { echo "ERROR: $F not found"; exit 1; }

# idempotent: the --stop pattern only matches while the broken flag remains
sed -i 's#--host 127.0.0.1#-r "<|im_end|>" -r "<|im_start|>" --host 127.0.0.1#' "$F"
systemctl daemon-reload
systemctl restart llama-server
sleep 3
echo "llama-server: $(systemctl is-active llama-server)"
