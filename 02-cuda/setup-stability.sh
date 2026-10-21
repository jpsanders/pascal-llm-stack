#!/bin/bash
# Stability hardening for long GPU renders on this laptop:
#  1. 16 GB swapfile on the Seagate store (OOM safety net; system stick stays lean)
#  2. GPU power limit 70 W (down from 88 W) - less heat, prevents thermal trips
# Run with:  sudo bash ~/nvidia-gpu-install/setup-stability.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

echo "=== [1/2] 16 GB swapfile on /mnt/ai-store ==="
SWAP=/mnt/ai-store/swapfile
if ! swapon --show=NAME | grep -q "^$SWAP$"; then
    fallocate -l 16G "$SWAP" 2>/dev/null || dd if=/dev/zero of="$SWAP" bs=1M count=16384 status=none
    chmod 600 "$SWAP"
    mkswap "$SWAP" > /dev/null
    if ! grep -q "^$SWAP " /etc/fstab; then
        echo "$SWAP none swap sw,nofail 0 0" >> /etc/fstab
    fi
    swapon "$SWAP"
fi
swapon --show
free -h | grep -i swap

echo
echo "=== [2/2] GPU power limit ==="
CUR=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | head -1)
echo "current power limit: ${CUR} W"
if [ "$CUR" -gt 70 ]; then
    if nvidia-smi -pl 70 2>/dev/null; then
        echo "power limit set to 70 W"
    else
        echo "70 W refused, trying 60 W..."
        nvidia-smi -pl 60 || echo "WARNING: could not set a power limit"
    fi
fi
nvidia-smi --query-gpu=power.limit --format=csv,noheader | head -1

echo
echo "=== hardening done ==="
echo "Note: the power limit resets on reboot; re-run this script (or add it to"
echo "a startup unit) after each boot before long renders."
