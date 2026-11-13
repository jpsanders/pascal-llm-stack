# pascal-llm

## NAME

pascal-llm - run local LLMs on a 2016 Pascal GPU under the newest Ubuntu and kernel

## SYNOPSIS

```
./pascal-llm steps
./pascal-llm run STEP
./pascal-llm status
./pascal-llm check
./pascal-llm guide
./pascal-llm man [--install | --raw]
./pascal-llm --version
```

## DESCRIPTION

pascal-llm-stack is a recipe, proven on one machine, for running local LLMs on a Pascal GPU (a GTX 1060 Mobile with
6 GB) under Ubuntu 26.04 and kernel 7.0: the NVIDIA 570 driver patched for kernel 7.0, CUDA 12.8 (the last branch that
compiles `sm_61`), llama.cpp built for the card, systemd services, a proxy that serves a chat page and an OpenAI style
API on port 8080, ComfyUI for images and video, Tailscale serving to your own devices only, and a smoke test that runs
after every kernel update. The 7B model serves about 22 tokens a second.

`pascal-llm` is the one entry point to the numbered scripts. Each step is a plain script you can read first; most
need sudo, and each says what it does when it starts.

## COMMANDS

| Command | What it does |
| --- | --- |
| `steps` | List the steps in order, with the script each one runs. |
| `run STEP` | Run one step. Most need sudo; the driver step reboots. |
| `status` | Read only: the kernel module, the GPU, CUDA, the three services and the API on 8080. |
| `check` | The smoke test: module, `nvidia-smi`, `libcuda` against the 570 userspace, a token rate on the GPU. |
| `guide` | Print this manual as Markdown, for people and agents. |
| `man` | Show this manual as a man page; `--install` makes `man pascal-llm` work. |

## STEPS

| Step | Script and what it does |
| --- | --- |
| `driver` | `01-driver/install-nvidia-driver.sh`: NVIDIA 570.211.01 with the kernel 7.0 patch, through DKMS. |
| `build-tools` | `02-cuda/setup-build-tools.sh`: compilers and build tools, without Ubuntu's CUDA package. |
| `cuda` | `02-cuda/install-cuda-toolkit.sh`: CUDA 12.8.1 from the runfile, toolkit only, with the glibc fix. |
| `llama` | `03-inference/build-llama-cpp.sh`: llama.cpp for `sm_61`, run as your own user. |
| `services` | `03-inference/setup-services.sh`: llama-server, the proxy on 8080 and ComfyUI as systemd services. |
| `tailscale` | `04-tailscale/setup-tailscale.sh`: Tailscale, with `tailscale serve` to your tailnet only. |
| `smoke-test` | `05-checks/install-smoke-test.sh`: the smoke test after every kernel update and at first boot. |
| `stability` | Optional. `02-cuda/setup-stability.sh`: a 16 GB swapfile and a 70 W power limit; edit the paths first. |
| `diffusion` | Optional. `03-inference/download-diffusion.sh`: image and video models; edit the paths first. |
| `big-model` | Optional. `03-inference/use-27b.sh`: a 27B model at about 2 tokens a second; set `MODEL`. |

## SERVICES AND PORTS

`llama-server` listens on 127.0.0.1:8090. `llama-web` is the proxy on 8080: a chat page and `/v1/*` streamed to
llama-server, and the one port Tailscale serves. `comfyui` listens on 127.0.0.1:8188. llama-server and ComfyUI
conflict on purpose, so starting one stops the other and the 6 GB of memory goes to one workload at a time.

## ENVIRONMENT

`MODEL` is the GGUF file for the services and the 27B switch. `COMFY_LISTEN` is ComfyUI's listen address, 127.0.0.1
by default; ComfyUI has no login, so open it to the network only on purpose. `XDG_DATA_HOME` moves the man folder
`man --install` writes to.

## FILES

The smoke test logs to the journal (`journalctl -u pascal-smoke-test`, tag `pascal-smoke`) and keeps its state in
`/var/lib/pascal-smoke`; a failed DKMS build is explained in `/var/lib/dkms/nvidia/<version>/build/make.log`. The
services are `/etc/systemd/system/llama-server.service`, `llama-web.service` and `comfyui.service`.

## EXIT STATUS

0 on success. 2 for an unknown command or step. `check` exits non zero when any part of the stack fails, and a `run`
exits with its script's status.

## EXAMPLES

From a fresh Ubuntu 26.04 install on a Pascal laptop:

```
./pascal-llm steps
sudo ./pascal-llm run driver          # reboots
sudo ./pascal-llm run build-tools
sudo ./pascal-llm run cuda
./pascal-llm run llama
sudo MODEL=/path/to/model.gguf ./pascal-llm run services
sudo ./pascal-llm run tailscale
sudo ./pascal-llm run smoke-test
./pascal-llm status
```

Any OpenAI client then talks to `http://127.0.0.1:8080/v1`, or to your machine's `ts.net` address from your other
devices.

## FOR AGENTS

Start with `./pascal-llm status` and `./pascal-llm steps`. Run steps in order, one at a time, and read each script
before running it: they install drivers, reboot and write system files, so each needs the person's go ahead. After a
kernel update, run `./pascal-llm check` before anything else. Use the API on port 8080 as an OpenAI compatible model
endpoint; never expose it with `tailscale funnel`.

## SEE ALSO

https://github.com/jpsanders/pascal-llm-stack

## AUTHOR

James Phillip Sanders, https://jamesphillipsanders.com
