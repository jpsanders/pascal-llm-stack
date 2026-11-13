# Security

Please report security problems privately, through GitHub's
[private vulnerability reporting](https://github.com/jpsanders/pascal-llm-stack/security/advisories/new), not in a
public issue.

## How the stack is exposed

- llama-server listens on 127.0.0.1:8090 and ComfyUI on 127.0.0.1:8188. Neither has a login.
- The proxy on 8080 is the one service meant for other devices, and only through `tailscale serve`, which reaches
  your own tailnet with TLS. Never use `tailscale funnel`, which would publish it to the internet.
- Before 1.2.0 ComfyUI listened on 0.0.0.0, open to the local network. Run the services step again, or edit
  `/etc/systemd/system/comfyui.service`, to close it.
- The driver and CUDA come from NVIDIA's own archives over HTTPS; the scripts never pipe a download into a shell.
