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
echo "=== [2/2] GPU power/clock limits ==="
CUR=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | head -1)
if [[ "$CUR" =~ ^[0-9]+$ ]]; then
    if [ "$CUR" -gt 70 ]; then
        nvidia-smi -pl 70 2>/dev/null || nvidia-smi -pl 60 || echo "power limit unsupported"
    fi
    echo "power limit: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader | head -1)"
else
    echo "power limit control: NOT SUPPORTED on this GPU (mobile GeForce)."
    nvidia-smi -lgc 1500,1500 2>/dev/null && echo "clock cap 1500 MHz set" || \
        echo "clock lock also unsupported - thermal mitigation must be physical"
fi
echo
echo "=== hardening done ==="
echo "Note: the power limit resets on reboot; re-run this script (or add it to"
echo "a startup unit) after each boot before long renders."
