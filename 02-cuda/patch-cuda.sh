#!/bin/bash
# Fix CUDA 12.8's crt/math_functions.h vs glibc 2.43 (Ubuntu 26.04) conflict.
#
# glibc 2.43 declares the C23 math functions cospi/sinpi/rsqrt (+float
# variants) as `noexcept(true)`, while CUDA 12.8's crt/math_functions.h
# declares the same functions WITHOUT an exception specification. cudafe++
# treats the mismatch as a hard, NON-suppressible error (EDG error 206):
#
#   mathcalls.h(83): error: exception specification is incompatible with
#   that of previous function "cospi" (declared at .../crt/math_functions.h)
#
# This is NVIDIA's own fix from CUDA 12.9, backported: append noexcept(true)
# to the six conflicting declarations. The original header is kept as .bak.
#
# Run with:  sudo bash 02-cuda/patch-cuda.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo bash $0"; exit 1; }

F=/usr/local/cuda-12.8/targets/x86_64-linux/include/crt/math_functions.h
[ -f "$F" ] || { echo "ERROR: $F not found (CUDA 12.8 toolkit installed?)"; exit 1; }

[ -f "$F.bak" ] || cp -n "$F" "$F.bak"

sed -i -E 's/^extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ (double|float) +(rsqrtf?|sinpif?|cospif?)\(([^)]*)\);/extern __DEVICE_FUNCTIONS_DECL__ __device_builtin__ \1 \2(\3) noexcept(true);/' "$F"

N=$(grep -c 'noexcept(true);' "$F")
echo "patched declarations: $N (expected 6)"
[ "$N" -eq 6 ] && echo "PATCH OK" || { echo "PATCH FAILED - restoring backup"; cp "$F.bak" "$F"; exit 1; }
