#!/bin/bash
# Build tools for llama.cpp (CUDA) + general CUDA development on Ubuntu 26.04.
# Run with:  sudo bash 02-cuda/setup-build-tools.sh
#
# NOTE: deliberately does NOT install Ubuntu's `nvidia-cuda-toolkit` package:
# it pulls Ubuntu's own 595-series driver userspace (libnvidia-compute-595),
# whose ldconfig would repoint libcuda.so.1 away from the NVIDIA-installer
# driver (570.211.01) and break CUDA against the 570 kernel module.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    g++-14 cmake ninja-build ccache libcurl4-openssl-dev pkg-config

echo
echo "Installed:"
g++-14 --version | head -1
cmake --version | head -1
ninja --version
