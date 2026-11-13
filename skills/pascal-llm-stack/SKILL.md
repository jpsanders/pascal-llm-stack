---
name: pascal-llm-stack
description: Set up, check or repair local LLM inference on an old NVIDIA Pascal GPU (GTX 1060 class, sm_61) under the newest Ubuntu and kernel with pascal-llm-stack: the patched 570 driver for kernel 7.0, CUDA 12.8, llama.cpp, systemd services, an OpenAI compatible API on port 8080 and Tailscale. Use when the user wants local LLMs on a Pascal card, when nvidia-smi or CUDA broke after a kernel update, or when the local model endpoint stopped answering.
---

# Local LLMs on a Pascal GPU with pascal-llm-stack

The repository holds numbered scripts and one entry point, `./pascal-llm`, run from a clone on the GPU machine.

## First, look

```sh
./pascal-llm status     # module, GPU, CUDA, the services, the API on 8080; read only
./pascal-llm steps      # the steps in order and the script each runs
```

## Setting up, step by step

Run the steps in this order, one at a time: `driver` (reboots), `build-tools`, `cuda`, `llama` (as the user, no
sudo), `services` (set `MODEL` to the GGUF file), `tailscale`, `smoke-test`. `stability`, `diffusion` and `big-model`
are optional and need paths edited first.

```sh
sudo ./pascal-llm run driver
```

## Rules

1. Every step installs drivers, writes system files or reboots. Read the script, tell the person what it will do,
   and run it only with their go ahead. Never chain several steps without asking.
2. After a kernel update, run `sudo ./pascal-llm check` before anything else; it names the failing layer and the fix.
3. Never install Ubuntu's `nvidia-cuda-toolkit` or the 580 or newer drivers on this card: they break the 570 stack.
4. Serve to the tailnet with `tailscale serve`, never `tailscale funnel`. ComfyUI has no login; keep it on 127.0.0.1.
5. Use `http://127.0.0.1:8080/v1` as an OpenAI compatible endpoint once the services run.

`./pascal-llm guide` prints the full manual.
