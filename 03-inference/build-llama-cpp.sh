#!/bin/bash
# Build llama.cpp with CUDA support for Pascal (sm_61) on Ubuntu 26.04.
# Run as your normal user:  bash 03-inference/build-llama-cpp.sh
#
# Requires: CUDA toolkit (02-cuda), g++-14 (02-cuda/setup-build-tools.sh).
# Produces build/bin/{llama-cli,llama-server,llama-bench}.
#
# Gotchas baked into this script (each one cost debugging time):
#  1. CMAKE_CUDA_COMPILER must point at nvcc explicitly - cmake does not
#     find /usr/local/cuda/bin/nvcc unless it is on PATH.
#  2. CMAKE_CUDA_HOST_COMPILER must be g++-14: CUDA 12.8 officially supports
#     gcc <= 14 and Ubuntu 26.04's default is gcc 15.
#  3. The whole toolchain is pinned to g++-14 (not just the CUDA part) so
#     there is exactly one ABI in the build.
#  4. GGML_CUDA=ON + CMAKE_CUDA_ARCHITECTURES=61 targets Pascal; a sm_60
#     cubin runs on sm_61 hardware (minor-revision binary compatibility).
set -euo pipefail

NVCC=/usr/local/cuda-12.8/bin/nvcc
[ -x "$NVCC" ] || { echo "ERROR: $NVCC not found - install the CUDA toolkit first"; exit 1; }
command -v g++-14 >/dev/null || { echo "ERROR: g++-14 missing - run 02-cuda/setup-build-tools.sh"; exit 1; }

[ -d "$HOME/llama.cpp" ] || git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$HOME/llama.cpp"

cd "$HOME/llama.cpp"
rm -rf build
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_COMPILER="$NVCC" \
    -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-14 \
    -DCMAKE_CUDA_ARCHITECTURES=61 \
    -DCMAKE_C_COMPILER=gcc-14 \
    -DCMAKE_CXX_COMPILER=g++-14 \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache
cmake --build build -j"$(nproc)" --target llama-cli llama-server llama-bench

echo
echo "=== Built binaries ==="
ls -la build/bin/llama-{cli,server,bench}
echo
echo "NOTE: the CUDA runtime libs are not on the default loader path. Either"
echo "export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:\$LD_LIBRARY_PATH"
echo "before running, or use the start-llm*.sh wrappers which set it."
