#!/bin/bash
# ============================================================================
# Checks the smoke test's verdicts without a GPU: fake dkms, nvidia-smi,
# ldconfig and systemctl on PATH, a fake module version, and a fake
# llama-server whose speed each case sets. CI runs it, and so can you:
#
#   bash 05-checks/test-smoke-test.sh
#   VERBOSE=1 bash 05-checks/test-smoke-test.sh   # also print each run
#
# It proves the logic (the two verdicts, the floor, the baseline, the results
# file and the exit status), not the stack: only a run on the GPU does that.
# ============================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SMOKE="$HERE/smoke-test.sh"
DRIVER="570.211.01"
T="$(mktemp -d)"
SERVER_PID=""
cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT

mkdir -p "$T/bin" "$T/lib" "$T/state"
touch "$T/lib/libcuda.so.$DRIVER"
ln -s "libcuda.so.$DRIVER" "$T/lib/libcuda.so.1"
echo "$DRIVER" > "$T/module-version"
echo 1 > "$T/on-gpu"

cat > "$T/bin/dkms" <<EOF
#!/bin/bash
echo "nvidia/$DRIVER, \$(uname -r), x86_64: installed"
EOF
cat > "$T/bin/nvidia-smi" <<EOF
#!/bin/bash
case "\$*" in
    *--query-gpu*) echo "NVIDIA GeForce GTX 1060 6GB, $DRIVER, 6.1" ;;
    *--query-compute-apps*) [ "\$(cat "$T/on-gpu")" = 1 ] && echo "llama-server" ;;
esac
exit 0
EOF
cat > "$T/bin/ldconfig" <<EOF
#!/bin/bash
printf '\tlibcuda.so.1 (libc6,x86-64) => %s\n' "$T/lib/libcuda.so.1"
EOF
printf '#!/bin/bash\nexit 3\n' > "$T/bin/systemctl"
chmod +x "$T/bin/"*

cat > "$T/server.py" <<'PY'
import http.server
import json
import os
import sys

STATE = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.send(200, {"status": "ok"}) if self.path == "/health" else self.send(404, {})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(os.path.join(STATE, "tps")) as fh:
            tps = float(fh.read())
        self.send(200, {"content": "The sea is calm.", "model": "/models/test-7b.Q5_K_M.gguf",
                        "timings": {"predicted_per_second": tps}})


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(os.path.join(STATE, "port"), "w") as fh:
    fh.write(str(server.server_port))
server.serve_forever()
PY
python3 "$T/server.py" "$T" &
SERVER_PID=$!
for _ in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
PORT="$(cat "$T/port")"

OUT=""; CODE=0; N=0; FAILED=0
run() {   # run the smoke test against the fakes, with any extra VAR=value settings
    OUT="$(env PATH="$T/bin:$PATH" MODULE_VERSION_FILE="$T/module-version" PASCAL_SMOKE_STATE="$T/state" \
        XDG_STATE_HOME="$T/user-state" LLAMA_URL="http://127.0.0.1:$PORT" "$@" bash "$SMOKE" 2>&1)"
    CODE=$?
}
check() { # description, the exit status wanted, a text the output must contain
    N=$((N + 1))
    if [ "$CODE" -eq "$2" ] && grep -qF -- "$3" <<< "$OUT"; then
        echo "ok $N - $1"
        [ "${VERBOSE:-0}" = 1 ] && sed 's/^/    /' <<< "$OUT"
    else
        echo "not ok $N - $1 (exit $CODE, wanted $2 and the text: $3)"
        sed 's/^/    /' <<< "$OUT"
        FAILED=$((FAILED + 1))
    fi
}
speed() { echo "$1" > "$T/tps"; }

speed 22.0; run
check "a first good run passes and starts the baseline" 0 "so it starts the baseline"
check "both verdicts are printed" 0 "workload: ok"
speed 21.6; run
check "ordinary variation passes against the baseline" 0 "PASS  generation: 21.6 tokens per second with test-7b.Q5_K_M.gguf (baseline 22.0"
speed 22.4; run
check "the baseline is the median of the good runs" 0 "baseline 21.8, the median of its last 2 good runs"
speed 17.0; run
check "a run well under the baseline warns and still passes" 0 "WARN  generation: 17.0 tokens per second with test-7b.Q5_K_M.gguf, 23% under the baseline of 22.0"
check "the warning names the last good run" 0 "Last good run: "
check "a slower run says so in the summary" 0 "workload: slower"
speed 9.0; run
check "a run under the floor fails the workload with exit 3" 3 "under the floor of 15"
check "the GPU verdict stays ok when only the workload fails" 3 "gpu: ok"
speed 22.0; echo 0 > "$T/on-gpu"; run
check "a server that left the GPU fails the workload" 3 "not on the GPU"
echo 1 > "$T/on-gpu"
run BASELINE_TPS=30
check "BASELINE_TPS pins the baseline" 0 "27% under the baseline of 30.0 (BASELINE_TPS)"
echo "565.77" > "$T/module-version"; run
check "a wrong module version fails the GPU layer with exit 1" 1 "gpu: broken (1 check(s) failed)"
echo "$DRIVER" > "$T/module-version"

N=$((N + 1))
lines=$(( $(wc -l < "$T/state/results.tsv") - 1 ))
header="$(head -1 "$T/state/results.tsv" | tr '\t' ' ')"
last="$(tail -1 "$T/state/results.tsv" | cut -f3- | tr '\t' ' ')"
if [ "$lines" -eq 8 ] && [ "$header" = "time_utc kernel driver gpu model tokens_per_second baseline gpu_state workload" ] \
    && [ "$last" = "565.77 NVIDIA GeForce GTX 1060 6GB test-7b.Q5_K_M.gguf 22.0 22.0 broken ok" ]; then
    echo "ok $N - every run left one line in results.tsv, with its versions and verdicts"
else
    echo "not ok $N - results.tsv holds $lines runs, wanted 8:"; sed 's/^/    /' "$T/state/results.tsv"
    FAILED=$((FAILED + 1))
fi

kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""
run
check "no llama-server fails the workload" 3 "no answer at"

echo "$((N - FAILED)) of $N passed"
[ "$FAILED" -eq 0 ]
