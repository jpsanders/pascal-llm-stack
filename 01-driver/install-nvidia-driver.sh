#!/bin/bash
# ============================================================================
# NVIDIA 570.211.01 (last Pascal-supporting legacy branch) for Ubuntu 26.04 /
# kernel 7.0 — fully self-contained: downloads the driver, applies the kernel
# 7.0 port patches, and installs via nvidia-installer + DKMS.
#
# Tested on: Ubuntu 26.04.1, kernel 7.0.0-30/38-generic, GTX 1060 Mobile 6GB
# (Pascal GP106M). SecureBoot disabled. Optimus laptop (Intel iGPU drives the
# display, NVIDIA GPU is compute-only).
#
# Run with:  sudo bash 01-driver/install-nvidia-driver.sh
# ============================================================================
set -euo pipefail

fail() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "run with sudo"

BASE_DIR="${NVIDIA_AI_DIR:-$HOME/nvidia-gpu-install}"
DRIVER_VER="570.211.01"
RUN_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VER}/NVIDIA-Linux-x86_64-${DRIVER_VER}-no-compat32.run"
PATCH_FILE="$(cd "$(dirname "$0")" && pwd)/kernel-7.0.patch"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

echo "=== [1/5] Prerequisites (dkms + headers for the running kernel) ==="
apt-get update -qq
apt-get install -y -qq dkms "linux-headers-$(uname -r)" patch curl
command -v dkms >/dev/null || fail "dkms failed to install"

echo "=== [2/5] Downloading NVIDIA ${DRIVER_VER} (291 MB) ==="
[ -f "NVIDIA-Linux-x86_64-${DRIVER_VER}-no-compat32.run" ] || \
    curl -fL --retry 10 --retry-delay 5 -o "NVIDIA-Linux-x86_64-${DRIVER_VER}-no-compat32.run" "$RUN_URL"
curl -fsL "https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VER}/NVIDIA-Linux-x86_64-${DRIVER_VER}-no-compat32.run.sha256sum" -o nvidia.sha256sum
sha256sum -c nvidia.sha256sum || fail "checksum mismatch"

echo "=== [3/5] Extracting + applying kernel 7.0 port patches ==="
rm -rf "nvidia-${DRIVER_VER}"
sh "NVIDIA-Linux-x86_64-${DRIVER_VER}-no-compat32.run" -x --target "nvidia-${DRIVER_VER}" > /dev/null
# Patch paths are prefixed "nvidia-pristine/kernel/" -> strip 2 components
patch -p2 -d "nvidia-${DRIVER_VER}" < "$PATCH_FILE"

echo "=== [4/5] Blacklisting nouveau + initramfs ==="
cat > /etc/modprobe.d/nvidia-disable-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
update-initramfs -u

echo "=== [5/5] Installing driver (userspace + DKMS kernel modules) ==="
cd "nvidia-${DRIVER_VER}"
./nvidia-installer \
    --silent --accept-license --no-questions --ui=none \
    --no-x-check \
    --dkms \
    --no-drm \
    --no-nouveau-check \
    --no-precompiled-interface \
    --skip-module-load \
    --no-backup \
    --rebuild-initramfs

echo
dkms status
for m in nvidia nvidia-uvm nvidia-modeset nvidia-peermem; do
    modinfo "$m" >/dev/null 2>&1 && echo "  $m: OK" || echo "  $m: NOT FOUND"
done

cat <<'EOF'

---------------------------------------------------------------
 Driver installed. REBOOT to activate:      sudo reboot
 After reboot verify with:                  nvidia-smi
---------------------------------------------------------------
 Notes:
  - nvidia-drm is intentionally excluded (does not compile on
    kernel 7.0; not needed for CUDA on Optimus laptops where the
    Intel iGPU drives the display).
  - DKMS auto-rebuilds for future kernels from the patched source
    registered in /usr/src/nvidia-570.211.01.
  - If a kernel was installed BEFORE this driver, run
    `sudo dkms autoinstall` after rebooting into it.
---------------------------------------------------------------
EOF
