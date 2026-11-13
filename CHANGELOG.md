# Changelog

Versions follow [semantic versioning](https://semver.org). Tags carry the bare version, such as `1.2.0`.

## 1.2.0 (2026-11-13)

- `pascal-llm`, one entry point: `steps`, `run <step>`, `status` (read only: module, GPU, CUDA, services, API),
  `check` (the smoke test), `guide` and `man`.
- A full manual, `docs/MANUAL.md`, built into `man/pascal-llm.1`.
- Security: ComfyUI's service now listens on 127.0.0.1 by default (`COMFY_LISTEN` opens it on purpose); it has no
  login and listened on every interface before.
- The first CI: every script parses, shellcheck finds no errors, the Python compiles, the workflows are valid JSON,
  the man page is current and the entry point answers. None of this needs a GPU; the steps themselves were not run
  again on the GPU for this release.
- A Claude Code plugin with a skill, AGENTS.md, llms.txt, a security note, a code of conduct, issue forms, Dependabot
  and a banner; no dashes left in the README prose.

## 1.1.0 (2026-11-10)

The smoke test after every kernel update (`05-checks`), and README section 10.

## 1.0.0 (2026-11-04)

The first release: driver, CUDA, llama.cpp, services, the proxy and web GUI, ComfyUI workflows and Tailscale.
