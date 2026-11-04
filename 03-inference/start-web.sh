#!/bin/bash
# Host the chat GUI + API proxy on 0.0.0.0:8080 (llama-server on 8090 behind it).
# Run as your normal user. Keep llama-server running (start-llm*.sh).
exec python3 ~/nvidia-gpu-install/llama-proxy.py
