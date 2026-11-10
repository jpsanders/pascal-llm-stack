#!/bin/bash
# ============================================================================
# Smoke test for the Pascal stack. Run it after every kernel update, or any
# time something feels off. It checks each layer that a kernel or package
# update can break, from the bottom up, and exits 1 if any check fails.
#
#   1. DKMS built the patched nvidia module for the running kernel
#   2. that module is the one loaded, at the expected version
#   3. nvidia-smi sees the GPU at the expected compute capability
#   4. libcuda.so.1 still points at the driver's own userspace
#      (apt's nvidia-cuda-toolkit repoints it, see README section 3)
#   5. llama-server answers, runs on the GPU, and generates at a sane speed
#
# Run by hand:   bash 05-checks/smoke-test.sh
# Installed:     sudo bash 05-checks/install-smoke-test.sh  (runs it on the
#                first boot of each new kernel, and checks the DKMS build
#                right after a kernel is installed, before you reboot)
#
# Settings (environment variables):
#   DRIVER_VERSION  default 570.211.01
#   COMPUTE_CAP     default 6.1 (GTX 10 series)
#   LLAMA_URL       default http://127.0.0.1:8090 (llama-server, not the proxy)
#   MIN_TPS         default 15 tokens per second. A GTX 1060 6 GB does about
#                   22 with a 7B at Q5_K_M fully in VRAM; a CPU fallback does
#                   a fraction of that, so anything under MIN_TPS fails.
#   WAIT_SECONDS    default 0; with --boot, 180. How long to wait for
#                   llama-server to load its model before giving up.
# ============================================================================
set -u

DRIVER_VERSION="${DRIVER_VERSION:-570.211.01}"
COMPUTE_CAP="${COMPUTE_CAP:-6.1}"
LLAMA_URL="${LLAMA_URL:-http://127.0.0.1:8090}"
MIN_TPS="${MIN_TPS:-15}"
STATE_DIR="/var/lib/pascal-smoke"
KVER="$(uname -r)"

BOOT=0
[ "${1:-}" = "--boot" ] && BOOT=1
WAIT_SECONDS="${WAIT_SECONDS:-$([ "$BOOT" -eq 1 ] && echo 180 || echo 0)}"

FAILS=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
skip() { echo "SKIP  $*"; }

if [ "$BOOT" -eq 1 ] && [ "$(cat "$STATE_DIR/last-pass-kernel" 2>/dev/null)" = "$KVER" ]; then
    echo "already passed on kernel $KVER"
    exit 0
fi

echo "kernel $KVER, driver $DRIVER_VERSION expected"

# 1. DKMS build for this kernel
if command -v dkms >/dev/null; then
    if dkms status -m nvidia -v "$DRIVER_VERSION" -k "$KVER" 2>/dev/null | grep -q ": installed"; then
        pass "dkms: nvidia $DRIVER_VERSION is built and installed for $KVER"
    else
        fail "dkms: no installed nvidia $DRIVER_VERSION build for $KVER (try: sudo dkms autoinstall -k $KVER, then read /var/lib/dkms/nvidia/$DRIVER_VERSION/build/make.log)"
    fi
else
    fail "dkms is not installed"
fi

# 2. the loaded module
if [ -r /sys/module/nvidia/version ]; then
    loaded="$(cat /sys/module/nvidia/version)"
    if [ "$loaded" = "$DRIVER_VERSION" ]; then
        pass "module: nvidia $loaded is loaded"
    else
        fail "module: nvidia $loaded is loaded, expected $DRIVER_VERSION"
    fi
else
    fail "module: nvidia is not loaded (sudo modprobe nvidia, then check dmesg)"
fi

# 3. nvidia-smi and the GPU
if command -v nvidia-smi >/dev/null; then
    if smi="$(nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>&1)"; then
        IFS=',' read -r gpu_name smi_driver smi_cap <<< "$(echo "$smi" | head -1)"
        gpu_name="$(echo "$gpu_name" | xargs)"; smi_driver="$(echo "$smi_driver" | xargs)"; smi_cap="$(echo "$smi_cap" | xargs)"
        if [ "$smi_driver" = "$DRIVER_VERSION" ] && [ "$smi_cap" = "$COMPUTE_CAP" ]; then
            pass "nvidia-smi: $gpu_name, driver $smi_driver, compute capability $smi_cap"
        else
            fail "nvidia-smi: $gpu_name, driver $smi_driver, compute capability $smi_cap (expected $DRIVER_VERSION and $COMPUTE_CAP)"
        fi
    else
        fail "nvidia-smi: $(echo "$smi" | head -1)"
    fi
else
    fail "nvidia-smi is not on PATH"
fi

# 4. libcuda.so.1 belongs to the same driver
libcuda="$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1 .*x86-64/ {print $NF; exit}')"
if [ -n "$libcuda" ]; then
    target="$(readlink -f "$libcuda")"
    case "$target" in
        *"$DRIVER_VERSION"*) pass "libcuda: $libcuda points at $target" ;;
        *) fail "libcuda: $libcuda points at $target, not the $DRIVER_VERSION userspace (an apt CUDA package may have repointed it)" ;;
    esac
else
    fail "libcuda: libcuda.so.1 is not in the linker cache"
fi

# 5. llama-server: up, on the GPU, and fast enough
waited=0
until curl -fsS -m 5 "$LLAMA_URL/health" >/dev/null 2>&1; do
    [ "$waited" -ge "$WAIT_SECONDS" ] && break
    sleep 5; waited=$((waited + 5))
done
if curl -fsS -m 5 "$LLAMA_URL/health" >/dev/null 2>&1; then
    if nvidia-smi --query-compute-apps=process_name --format=csv,noheader 2>/dev/null | grep -q "llama-server"; then
        pass "llama-server: answering at $LLAMA_URL and holding GPU memory"
    else
        fail "llama-server: answering, but not on the GPU (it may have fallen back to the CPU)"
    fi
    body='{"prompt":"Write one sentence about the sea.","n_predict":64,"temperature":0,"cache_prompt":false}'
    if reply="$(curl -fsS -m 120 -H 'Content-Type: application/json' -d "$body" "$LLAMA_URL/completion" 2>&1)"; then
        tps="$(printf '%s' "$reply" | python3 -c 'import json,sys; print(round(json.load(sys.stdin)["timings"]["predicted_per_second"], 1))' 2>/dev/null)"
        if [ -z "$tps" ]; then
            fail "generation: no timings in the reply"
        elif python3 -c "import sys; sys.exit(0 if float('$tps') >= float('$MIN_TPS') else 1)"; then
            pass "generation: $tps tokens per second (at least $MIN_TPS)"
        else
            fail "generation: $tps tokens per second, under $MIN_TPS"
        fi
    else
        fail "generation: the completion request failed: $(echo "$reply" | head -1)"
    fi
else
    if systemctl is-active --quiet comfyui 2>/dev/null; then
        skip "llama-server: not running because comfyui holds the GPU (sudo systemctl start llama-server, then run this again)"
    else
        fail "llama-server: no answer at $LLAMA_URL/health after ${WAIT_SECONDS}s"
    fi
fi

if [ "$FAILS" -eq 0 ]; then
    echo "all checks passed on kernel $KVER"
    if [ -w "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null; then
        echo "$KVER" > "$STATE_DIR/last-pass-kernel" 2>/dev/null || true
    fi
    exit 0
fi
echo "$FAILS check(s) failed on kernel $KVER"
exit 1
