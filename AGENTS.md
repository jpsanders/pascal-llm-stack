# AGENTS.md

Instructions for AI coding agents working on pascal-llm-stack itself. To use it on a GPU machine, read
`skills/pascal-llm-stack/SKILL.md` or run `./pascal-llm guide`.

## Commands

```sh
./pascal-llm steps                          # the steps and their scripts
python3 scripts/build_man.py                # rebuild man/pascal-llm.1 after editing docs/MANUAL.md
shellcheck --severity=error pascal-llm $(git ls-files '*.sh')   # what CI runs, with bash -n and py_compile
```

## Rules

- The scripts only run for real on a Pascal GPU. Never claim a change works on the GPU unless it ran there; say what
  was checked (syntax, shellcheck, a dry read) and what was not.
- Keep the repository clean and safe for work: no NSFW, uncensored or abliterated model names in files, commits or
  release notes.
- A new step gets a line in the `STEPS` list in `pascal-llm`, a row in `docs/MANUAL.md` and a section in the README.
- Services listen on 127.0.0.1; only the proxy on 8080 is served, and only with `tailscale serve`.
- Tags carry the bare version, `1.2.0`, never `v1.2.0`.
