#!/bin/bash
# Install Tailscale and expose the local llama-server on your tailnet.
# Run with:  sudo bash ~/nvidia-gpu-install/setup-tailscale.sh
#
# SECURITY: uses `tailscale serve` (tailnet-only, TLS-encrypted).
# NOT `tailscale funnel` (that would expose the server to the public internet).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

echo "=== Installing Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh

echo
echo "=== Bringing up Tailscale (login required) ==="
echo "A login URL will print below. Open it on ANY device, log in,"
echo "and approve THIS machine. Then come back here."
echo
tailscale up

echo
echo "=== Exposing llama-server (http://127.0.0.1:8080) on your tailnet ==="
tailscale serve --bg 8080

echo
echo "=== Tailscale status ==="
tailscale status | head -5
echo
echo "Your machine's tailnet URL (use this from capivara):"
tailscale status --self --json | grep -oE 'https://[^"]*ts\.net' | head -1 || true
echo
echo "LLM API (from capivara):  https://<your-host>.ts.net/v1/chat/completions"
echo "Web UI   (from capivara): https://<your-host>.ts.net/"
