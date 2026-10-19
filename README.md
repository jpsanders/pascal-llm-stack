# pascal-llm-stack

A working recipe for running local LLMs on a Pascal-era GPU (GTX 1060) under the newest Ubuntu and the newest kernel.

The driver said unsupported. CUDA said unsupported. PyTorch's wheels said unsupported. The GPU is fine — 6 GB of 2016 silicon serves 22 tokens per second once every layer of the stack is told the truth about the year. Every claim here was executed and benchmarked on Ubuntu 26.04.1, kernel 7.0.0-30/38, GTX 1060 Mobile 6 GB (Optimus, Intel iGPU drives the display), 12 threads, 30 GB RAM.

## 1. The distro recommends a driver that cannot drive the card

`ubuntu-drivers` offers `nvidia-driver-580`. NVIDIA dropped Pascal after branch 570, so 580 will never bind to the GPU. Worse, `apt-cache policy nvidia-driver-570` reports candidate `580.178.04` — the "570" package is a transitional pointer to 580. The only real legacy branch is NVIDIA's own `.run` from the Unix archive, and it does not compile on kernel 7.0 out of the box. `01-driver/install-nvidia-driver.sh` downloads it, patches it (see `kernel-7.0.patch`, 6 files), installs with DKMS, and reboots into a working `nvidia-smi`.

## 2. The 570 kernel module predates kernel 7.0 by a year

Four separate kernel API rewrites break the build. The patch fixes each, version-guarded so the same source still builds on older kernels:

| Kernel 7.0 change | Fix in `kernel-7.0.patch` |
|---|---|
| `in_irq()` removed | switch to `in_hardirq()` in `nv-time.h`, `os-interface.c` |
| `struct dma_map_ops::map_resource` removed | peer-DMA via dma_map_ops disabled; the `dma_map_resource()` function itself still exists |
| `vm_area_struct.__vm_flags` gone; `vm_flags` is a `const` bitmap behind a union | use the kernel's inline `vma_flags_set_word()`/`vma_flags_clear_word()` |
| VMA locking redesigned: `VMA_LOCK_OFFSET` gone, `__is_vma_write_locked()` takes one arg, refcount uses `VM_REFCNT_EXCLUDE_READERS_FLAG` bits | NVIDIA's open-coded GPL workaround rewritten per the 7.0 protocol documented in `mm_types.h`: set the exclude-readers flag, drain readers on `mm->vma_writer_wait`, `WRITE_ONCE(vm_lock_seq)`, clear the flag — non-GPL inline helpers only |

The last one is the interesting one: `vm_flags_set()` is a static inline in `mm.h`, but it calls the GPL-only `__vma_start_write()`, which a proprietary module may not reference — that is why NVIDIA open-coded the lock in the first place. The new protocol was fully documented in the `vm_area_struct` comments, which was enough to re-implement it.

Two installer flags matter on top of the patch: `--no-drm` (the DRM module has its own API churn and is not needed for CUDA on Optimus laptops where the iGPU drives the display) and `--no-x-check` (silent mode auto-aborts while X is running otherwise). DKMS builds for the running kernel only — a kernel installed *before* the driver needs `sudo dkms autoinstall` after booting into it.

## 3. `apt install nvidia-cuda-toolkit` quietly breaks the driver you just installed

The package depends on `libnvidia-compute-595`. Its ldconfig repoints `libcuda.so.1` away from the 570.211.01 userspace, and a userspace/kernel version mismatch breaks CUDA at init. Instead, use NVIDIA's runfile with `--toolkit`: it installs to `/usr/local/cuda-12.8` and touches nothing else. `02-cuda/install-cuda-toolkit.sh` does this, plus the two fixes below.

Why 12.8 and not 13: CUDA 13 removed Pascal compilation. 12.8 is the last branch that targets `sm_61` and the first that officially supports the gcc-14 host compiler.

## 4. The CUDA installer is linked against a libxml2 that no longer exists

Ubuntu 26.04 ships libxml2 with SONAME `.so.16` (major bump). The installer binary wants `libxml2.so.2` and dies before printing a single useful message. The fix is zero-pollution: `dpkg -x` the genuine `libxml2.so.2` out of the 24.04 LTS pool into a side directory and run the installer with `LD_LIBRARY_PATH` pointing at it.

## 5. The toolkit cannot parse the system glibc

Two separate checks, two separate fixes. First the installer refuses gcc 15 (`unsupported compiler version`) — harmless for a toolkit install that compiles nothing, so `--override`. Then, once you compile anything, cudafe++ dies on glibc 2.43's new C23 math declarations:

```
mathcalls.h(83): error: exception specification is incompatible with
that of previous function "cospi" (declared at .../crt/math_functions.h)
```

`--diag_suppress` does not work — EDG treats declaration merging as a hard error. `02-cuda/patch-cuda.sh` backports NVIDIA's own CUDA-12.9 fix: append `noexcept(true)` to the six conflicting declarations in `crt/math_functions.h` (backup kept as `.bak`).

## 6. PyTorch wheels dropped your GPU

torch 2.11+cu128 ships kernels for `sm_75` and up; importing it next to a CC 6.1 GPU warns and fails. The last wheel series with Pascal kernels is 2.7.x, and a `sm_60` cubin runs on `sm_61` (minor-revision binary compatibility):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv venv ~/ml-venv --python 3.12
uv pip install numpy torch==2.7.1 --index-url https://download.pytorch.org/whl/cu126
python -c "import torch; assert 'sm_60' in torch.cuda.get_arch_list()"
```

`get_arch_list()` is the truth, not the marketing page. Pin the version.

## 7. llama.cpp is three cmake flags away from a build

`03-inference/build-llama-cpp.sh` contains them: `-DCMAKE_CUDA_COMPILER` pointed at nvcc explicitly (cmake does not search `/usr/local/cuda/bin`), `-DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-14` (the gcc-15 default is unsupported), and `-DCMAKE_CUDA_ARCHITECTURES=61`. `GGML_CUDA=ON` produces `libggml-cuda.so` with Pascal kernels; the resulting `llama-server` speaks the OpenAI API and ships a web UI.

## 8. Six gigabytes of VRAM: the DDR4 tail dominates

Partial offload (`-ngl N`) splits transformer blocks between VRAM and system RAM. Token generation re-reads every weight, so the CPU-resident fraction is capped by DDR4 (~40 GB/s) while the GPU fraction runs at ~120 GB/s. Measured with `llama-bench`:

| Model | Config | Prompt | Generation |
|---|---|---|---|
| Qwen3.8-27B Q4_K_XL (16.2 GiB) | `-ngl 16` | 69 t/s | 1.96 t/s |
| Qwen3.8-27B Q4_K_XL | `-ngl 20` | 70 t/s | 2.05 t/s |
| Qwen3.8-27B Q4_K_XL | `-ngl 24` | OOM — needs 6360 MiB | |
| MistralRP 7B Q5_K_M (4.78 GiB) | `-ngl 99` | 338 t/s | 22.4 t/s |

Beyond ~20 layers, adding more moves generation by 0.09 t/s. The DDR4 tail dominates. The ten-x lever is choosing a model that fits **entirely** in VRAM — a 7B at Q5 beats a 27B at Q4 by an order of magnitude on this card. Prompt processing stays fast either way; it parallelizes.

One more data point: OpenCode's agent system prompt alone is **51k tokens**. With
`--no-kv-offload` (KV in system RAM), every generated token re-reads that ~3.3 GB
of KV over PCIe: generation drops to **1.9 t/s at 51k context** even though the
same model does 22 t/s at chat-length contexts. Agent frameworks with huge fixed
prompts are a bad match for small-VRAM GPUs; use them with cloud models and keep
the local GPU for chat-length workloads.

Corollary: check repo file sizes before falling in love with a model. "GLM-5.3-Flash" is ~200 GB at Q4 (six 50 GB shards), a 753B flagship is ~1.5 TB in BF16. Neither fits on a 56 GB disk, in 30 GB of RAM, or in 6 GB of VRAM. `-fa on -ctk q8_0 -ctv q8_0` halves the KV cache when a model barely fits; `pkill -x llama-server` stops a server without killing your own shell (the `-f` variant matches your own command line).

## 9. Serve it to the tailnet, not the internet

`04-tailscale/setup-tailscale.sh` installs Tailscale and runs `tailscale serve --bg 8080`: the loopback-only server appears as `https://<host>.<tailnet>.ts.net` with valid TLS, reachable only by your own devices. No inbound ports, no port forwarding, no allow lists — Tailscale is outbound-only (UDP 41641, TCP 443 fallback). From another machine:

```bash
curl https://<host>.<tailnet>.ts.net/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hi"}]}'
```

## Layout

```
01-driver/    install-nvidia-driver.sh, kernel-7.0.patch
02-cuda/      setup-build-tools.sh, install-cuda-toolkit.sh, patch-cuda.sh
03-inference/ build-llama-cpp.sh, start-llm.sh (27B), start-llm-mistral.sh (7B)
04-tailscale/ setup-tailscale.sh
```

## License

MIT. The scripts and the kernel patch are original work; NVIDIA and llama.cpp artifacts are referenced by URL and patched in place, never redistributed.
