#!/bin/bash
# Install the official NVIDIA CUDA 12.8.1 toolkit (runfile, toolkit-only).
#
# Why 12.8: the last CUDA branch that still compiles Pascal (sm_61; CUDA 13
# dropped it) while officially supporting the gcc-14 host compiler.
#
# Why the runfile and not Ubuntu's nvidia-cuda-toolkit package: see the note
# in setup-build-tools.sh (driver-userspace conflict).
#
# Run with:  sudo bash 02-cuda/install-cuda-toolkit.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

BASE_DIR="${NVIDIA_AI_DIR:-$HOME/nvidia-gpu-install}"
CUDA_VER="12.8.1"
RUNFILE="$BASE_DIR/cuda_${CUDA_VER}_570.124.06_linux.run"
RUN_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VER}/local_installers/cuda_${CUDA_VER}_570.124.06_linux.run"

mkdir -p "$BASE_DIR"
if [ ! -f "$RUNFILE" ]; then
    echo "=== Downloading CUDA ${CUDA_VER} runfile (~5.4 GB) ==="
    curl -fL --retry 10 --retry-delay 5 -o "$RUNFILE" "$RUN_URL"
fi
SIZE=$(stat -c %s "$RUNFILE")
[ "$SIZE" -ge 4000000000 ] || { echo "ERROR: runfile incomplete ($SIZE bytes)"; exit 1; }

echo "=== Installing CUDA toolkit to /usr/local/cuda-${CUDA_VER%%.*} (no driver changes) ==="

# --- Compatibility shim 1: libxml2 SONAME -------------------------------------
# The CUDA installer binary is linked against libxml2.so.2, but Ubuntu 26.04
# ships libxml2 with SONAME .so.16 (major version bump). Extract the genuine
# legacy libxml2.so.2 from the 24.04 LTS pool and feed it via LD_LIBRARY_PATH
# (nothing is installed system-wide).
COMPAT="$BASE_DIR/cuda-compat-libs"
mkdir -p "$COMPAT"
if [ ! -f "$COMPAT/usr/lib/x86_64-linux-gnu/libxml2.so.2" ]; then
    curl -fsSL -o "$COMPAT/libxml2.deb" \
        "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.12.7+dfsg+really2.9.14-0.4ubuntu0.4_amd64.deb"
    dpkg -x "$COMPAT/libxml2.deb" "$COMPAT"
    rm -f "$COMPAT/libxml2.deb"
fi
export LD_LIBRARY_PATH="$COMPAT/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# --- Install ------------------------------------------------------------------
# --override: skip the gcc version check (system gcc may be newer than the
# officially supported one; the toolkit ships prebuilt binaries and compiles
# nothing during install — compilation later uses g++-14 explicitly).
sh "$RUNFILE" --silent --toolkit --override

echo "Reclaiming disk: removing the CUDA runfile..."
rm -f "$RUNFILE"

echo
/usr/local/cuda/bin/nvcc --version || /usr/local/cuda-12.8/bin/nvcc --version
