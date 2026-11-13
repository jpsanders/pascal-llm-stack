# Contributing

Issues and pull requests are welcome, especially results from other Pascal cards and kernels. Say which card, kernel
and Ubuntu, and paste `./pascal-llm status`.

CI checks what it can without a GPU: every script parses, shellcheck finds no errors, the Python compiles, the ComfyUI
workflows are valid JSON, the man page matches `docs/MANUAL.md`, and the entry point answers. A change to a step also
needs a real run on a Pascal GPU; say so in the pull request.
