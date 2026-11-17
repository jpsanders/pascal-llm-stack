# Changelog

Versions follow [semantic versioning](https://semver.org). Tags carry the bare version, such as `1.2.0`.

## 1.3.0 (2026-11-17)

- The smoke test answers two questions separately: is the GPU available (checks 1 to 4), and does the workload still
  behave (check 5). It exits 1 when the GPU layer fails and 3 when only the workload does; before, any failure exited 1.
- Every run appends a line to `results.tsv`: the time, kernel, loaded driver, GPU, model, tokens per second, the
  baseline and both verdicts.
- The speed is compared with a baseline, the median of the model's last five good runs or `BASELINE_TPS`. A run more
  than `DRIFT_PCT` (15) percent under it is a warning that names the last good run's kernel and driver; `MIN_TPS`
  stays the floor.
- `05-checks/test-smoke-test.sh` checks those verdicts in CI with a fake GPU and a fake llama-server. The new speed
  logic has not run on the GPU yet.
- An installed smoke test updates when you run `sudo bash 05-checks/install-smoke-test.sh` again.

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
