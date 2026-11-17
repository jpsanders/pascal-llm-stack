#!/bin/bash
# ============================================================================
# Smoke test for the Pascal stack. Run it after every kernel update, or any
# time something feels off. It answers two questions separately, each from
# the bottom up, so a broken update is told apart from ordinary variation.
#
# Is the GPU available?
#   1. DKMS built the patched nvidia module for the running kernel
#   2. that module is the one loaded, at the expected version
#   3. nvidia-smi sees the GPU at the expected compute capability
#   4. libcuda.so.1 still points at the driver's own userspace
#      (apt's nvidia-cuda-toolkit repoints it, see README section 3)
#
# Does the workload still behave?
#   5. llama-server answers, runs on the GPU, generates above the floor, and
#      is compared with this model's baseline
#
# Every run appends one line to results.tsv: the time, kernel, loaded driver,
# GPU, model, tokens per second, the baseline and both verdicts.
#
# Exit status: 0 when both questions pass (a speed under the baseline is a
# warning, not a failure), 1 when the GPU layer fails, 3 when the GPU is fine
# but the workload is not.
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
#   MIN_TPS         default 15 tokens per second, the floor. A CPU fallback
#                   lands far under it, so a slower run fails.
#   BASELINE_TPS    default: the median of this model's last 5 good runs in
#                   results.tsv. Set it to pin a number; a GTX 1060 6 GB does
#                   about 22 with a 7B at Q5_K_M fully in VRAM.
#   DRIFT_PCT       default 15. A run more than this many percent under the
#                   baseline is a warning that names the last good run.
#   WAIT_SECONDS    default 0; with --boot, 180. How long to wait for
#                   llama-server to load its model before giving up.
#   PASCAL_SMOKE_STATE   default /var/lib/pascal-smoke: the boot state and
#                   results.tsv. A run by hand without write access there
#                   keeps its results in ~/.local/state/pascal-smoke instead.
#   MODULE_VERSION_FILE  default /sys/module/nvidia/version (the tests set it)
# ============================================================================
set -u

DRIVER_VERSION="${DRIVER_VERSION:-570.211.01}"
COMPUTE_CAP="${COMPUTE_CAP:-6.1}"
LLAMA_URL="${LLAMA_URL:-http://127.0.0.1:8090}"
MIN_TPS="${MIN_TPS:-15}"
BASELINE_TPS="${BASELINE_TPS:-}"
DRIFT_PCT="${DRIFT_PCT:-15}"
STATE_DIR="${PASCAL_SMOKE_STATE:-/var/lib/pascal-smoke}"
USER_STATE_DIR="${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/pascal-smoke"
MODULE_VERSION_FILE="${MODULE_VERSION_FILE:-/sys/module/nvidia/version}"
KVER="$(uname -r)"

BOOT=0
[ "${1:-}" = "--boot" ] && BOOT=1
WAIT_SECONDS="${WAIT_SECONDS:-$([ "$BOOT" -eq 1 ] && echo 180 || echo 0)}"

GPU_FAILS=0
WORKLOAD="ok"   # ok, slower, broken or skipped
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; }
skip() { echo "SKIP  $*"; }
gpu_fail() { echo "FAIL  $*"; GPU_FAILS=$((GPU_FAILS + 1)); }
work_fail() { echo "FAIL  $*"; WORKLOAD="broken"; }

if [ "$BOOT" -eq 1 ] && [ "$(cat "$STATE_DIR/last-pass-kernel" 2>/dev/null)" = "$KVER" ]; then
    echo "already passed on kernel $KVER"
    exit 0
fi

# Results go next to the boot state when this run may write there.
if [ -w "$STATE_DIR" ] || { [ ! -e "$STATE_DIR" ] && mkdir -p "$STATE_DIR" 2>/dev/null; }; then
    RESULTS="$STATE_DIR/results.tsv"
else
    RESULTS="$USER_STATE_DIR/results.tsv"
fi

# The baseline for a model, from both results files: prints
# verdict|baseline|percent under|where the baseline came from|the last good run
compare_baseline() {
    python3 - "$1" "$2" "$BASELINE_TPS" "$DRIFT_PCT" "$STATE_DIR/results.tsv" "$USER_STATE_DIR/results.tsv" <<'PY'
import csv
import statistics
import sys

model, tps, pinned, drift = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4])
rows = []
for path in dict.fromkeys(sys.argv[5:]):
    try:
        with open(path, newline="") as fh:
            rows += list(csv.DictReader(fh, delimiter="\t"))
    except OSError:
        pass
good = [r for r in rows if r.get("model") == model and r.get("workload") == "ok"
        and r.get("tokens_per_second", "-") not in ("", "-")]
good.sort(key=lambda r: r.get("time_utc", ""))
last = good[-1] if good else None
if pinned:
    baseline, source = float(pinned), "BASELINE_TPS"
elif good:
    recent = [float(r["tokens_per_second"]) for r in good[-5:]]
    baseline = statistics.median(recent)
    source = f"the median of its last {len(recent)} good run{'s' if len(recent) > 1 else ''}"
else:
    print("first||0|no earlier good run of this model|")
    sys.exit(0)
under = max(0.0, (baseline - tps) / baseline * 100) if baseline > 0 else 0.0
verdict = "slower" if under > drift else "ok"
seen = ""
if last:
    seen = (f"{last.get('time_utc')} on kernel {last.get('kernel')}, driver {last.get('driver')}, "
            f"{last.get('tokens_per_second')} tokens per second")
print(f"{verdict}|{baseline:.1f}|{under:.0f}|{source}|{seen}")
PY
}

record() {
    mkdir -p "$(dirname "$RESULTS")" 2>/dev/null
    if [ ! -s "$RESULTS" ]; then
        printf 'time_utc\tkernel\tdriver\tgpu\tmodel\ttokens_per_second\tbaseline\tgpu_state\tworkload\n' \
            >> "$RESULTS" 2>/dev/null || return 1
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$KVER" "${loaded:-none}" \
        "${gpu_name:-none}" "$model" "${tps:--}" "${baseline:--}" "$gpu_state" "$WORKLOAD" >> "$RESULTS" 2>/dev/null
}

echo "kernel $KVER, driver $DRIVER_VERSION expected"
echo "Is the GPU available?"

# 1. DKMS build for this kernel
if command -v dkms >/dev/null; then
    if dkms status -m nvidia -v "$DRIVER_VERSION" -k "$KVER" 2>/dev/null | grep -q ": installed"; then
        pass "dkms: nvidia $DRIVER_VERSION is built and installed for $KVER"
    else
        gpu_fail "dkms: no installed nvidia $DRIVER_VERSION build for $KVER (try: sudo dkms autoinstall -k $KVER, then read /var/lib/dkms/nvidia/$DRIVER_VERSION/build/make.log)"
    fi
else
    gpu_fail "dkms is not installed"
fi

# 2. the loaded module
if [ -r "$MODULE_VERSION_FILE" ]; then
    loaded="$(cat "$MODULE_VERSION_FILE")"
    if [ "$loaded" = "$DRIVER_VERSION" ]; then
        pass "module: nvidia $loaded is loaded"
    else
        gpu_fail "module: nvidia $loaded is loaded, expected $DRIVER_VERSION"
    fi
else
    gpu_fail "module: nvidia is not loaded (sudo modprobe nvidia, then check dmesg)"
fi

# 3. nvidia-smi and the GPU
if command -v nvidia-smi >/dev/null; then
    if smi="$(nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>&1)"; then
        IFS=',' read -r gpu_name smi_driver smi_cap <<< "$(echo "$smi" | head -1)"
        gpu_name="$(echo "$gpu_name" | xargs)"; smi_driver="$(echo "$smi_driver" | xargs)"; smi_cap="$(echo "$smi_cap" | xargs)"
        if [ "$smi_driver" = "$DRIVER_VERSION" ] && [ "$smi_cap" = "$COMPUTE_CAP" ]; then
            pass "nvidia-smi: $gpu_name, driver $smi_driver, compute capability $smi_cap"
        else
            gpu_fail "nvidia-smi: $gpu_name, driver $smi_driver, compute capability $smi_cap (expected $DRIVER_VERSION and $COMPUTE_CAP)"
        fi
    else
        gpu_fail "nvidia-smi: $(echo "$smi" | head -1)"
    fi
else
    gpu_fail "nvidia-smi is not on PATH"
fi

# 4. libcuda.so.1 belongs to the same driver
libcuda="$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1 .*x86-64/ {print $NF; exit}')"
if [ -n "$libcuda" ]; then
    target="$(readlink -f "$libcuda")"
    case "$target" in
        *"$DRIVER_VERSION"*) pass "libcuda: $libcuda points at $target" ;;
        *) gpu_fail "libcuda: $libcuda points at $target, not the $DRIVER_VERSION userspace (an apt CUDA package may have repointed it)" ;;
    esac
else
    gpu_fail "libcuda: libcuda.so.1 is not in the linker cache"
fi

echo "Does the workload still behave?"

# 5. llama-server: up, on the GPU, above the floor, and near its baseline
model="none"; tps=""; baseline=""
waited=0
until curl -fsS -m 5 "$LLAMA_URL/health" >/dev/null 2>&1; do
    [ "$waited" -ge "$WAIT_SECONDS" ] && break
    sleep 5; waited=$((waited + 5))
done
if curl -fsS -m 5 "$LLAMA_URL/health" >/dev/null 2>&1; then
    if nvidia-smi --query-compute-apps=process_name --format=csv,noheader 2>/dev/null | grep -q "llama-server"; then
        pass "llama-server: answering at $LLAMA_URL and holding GPU memory"
    else
        work_fail "llama-server: answering, but not on the GPU (it may have fallen back to the CPU)"
    fi
    body='{"prompt":"Write one sentence about the sea.","n_predict":64,"temperature":0,"cache_prompt":false}'
    if reply="$(curl -fsS -m 120 -H 'Content-Type: application/json' -d "$body" "$LLAMA_URL/completion" 2>&1)"; then
        parsed="$(printf '%s' "$reply" | python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
    tps = round(float(d["timings"]["predicted_per_second"]), 1)
except Exception:
    sys.exit(0)
name = os.path.basename(str(d.get("model") or "")).replace("|", "/").replace("\t", " ")
print(str(tps) + "|" + (name or "unknown"))
' 2>/dev/null)"
        if [ -z "$parsed" ]; then
            model="unknown"
            work_fail "generation: no timings in the reply"
        else
            tps="${parsed%%|*}"; model="${parsed#*|}"
            if ! python3 -c "import sys; sys.exit(0 if float('$tps') >= float('$MIN_TPS') else 1)"; then
                work_fail "generation: $tps tokens per second with $model, under the floor of $MIN_TPS (a CPU fallback, or a broken update)"
            else
                IFS='|' read -r verdict baseline under source lastgood <<< "$(compare_baseline "$model" "$tps")"
                case "${verdict:-}" in
                    first)
                        pass "generation: $tps tokens per second with $model (floor $MIN_TPS; the first good run of this model, so it starts the baseline)" ;;
                    ok)
                        pass "generation: $tps tokens per second with $model (baseline $baseline, $source; floor $MIN_TPS)" ;;
                    slower)
                        warn "generation: $tps tokens per second with $model, ${under}% under the baseline of $baseline ($source). Last good run: ${lastgood:-none}. Not a failure: compare its kernel and driver with this run's before trusting the update."
                        [ "$WORKLOAD" = "ok" ] && WORKLOAD="slower" ;;
                    *)
                        warn "generation: $tps tokens per second with $model; the baseline could not be read from $RESULTS" ;;
                esac
            fi
        fi
    else
        work_fail "generation: the completion request failed: $(echo "$reply" | head -1)"
    fi
else
    if systemctl is-active --quiet comfyui 2>/dev/null; then
        skip "llama-server: not running because comfyui holds the GPU (sudo systemctl start llama-server, then run this again)"
        WORKLOAD="skipped"
    else
        work_fail "llama-server: no answer at $LLAMA_URL/health after ${WAIT_SECONDS}s"
    fi
fi

gpu_state="ok"
[ "$GPU_FAILS" -gt 0 ] && gpu_state="broken"
if record; then saved="saved to $RESULTS"; else saved="not saved: $RESULTS is not writable"; fi
if [ "$GPU_FAILS" -gt 0 ]; then
    echo "gpu: broken ($GPU_FAILS check(s) failed)"
else
    echo "gpu: ok"
fi
echo "workload: $WORKLOAD"
echo "result $saved"

if [ "$GPU_FAILS" -gt 0 ]; then
    echo "the GPU layer failed on kernel $KVER"
    exit 1
fi
if [ "$WORKLOAD" = "broken" ]; then
    echo "the GPU is available, but the workload failed on kernel $KVER"
    exit 3
fi
if [ "$WORKLOAD" = "slower" ]; then
    echo "all checks passed on kernel $KVER, slower than the baseline: see the WARN line"
else
    echo "all checks passed on kernel $KVER"
fi
if [ -w "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null; then
    echo "$KVER" > "$STATE_DIR/last-pass-kernel" 2>/dev/null || true
fi
exit 0
