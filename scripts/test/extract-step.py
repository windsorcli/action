#!/usr/bin/env python3
"""Extract one step's script from a composite action.yaml, to test it in isolation.

Composite actions can't be unit-tested step-by-step through `uses:` alone —
some steps (like plan-comment's github-script call) have real side effects
(posting to the GitHub API) that a test must not trigger. This pulls a single
step's script out so it can be run directly against a stub `windsor` or
mocked core/github/context objects instead.

Usage:
  extract-step.py <action.yaml> <step-index> [--wrap-js]

Prints the extracted script to stdout:
- For a `run:` step, the raw shell script, with the
  `${{ github.action_path }}/../scripts/lib.sh` reference rewritten to an
  absolute path (there's no real action_path outside an actual Actions run).
- For a `uses: actions/github-script` step (pass --wrap-js), the `with.script`
  text wrapped as `async function main(core, github, context) { ... }` so it
  can be require()'d and driven with mocks — see plan-comment.test.js.
"""
import os
import sys

import yaml


def main() -> None:
    action_file, step_index = sys.argv[1], int(sys.argv[2])
    wrap_js = "--wrap-js" in sys.argv[3:]

    with open(action_file) as f:
        data = yaml.safe_load(f)
    step = data["runs"]["steps"][step_index]

    if wrap_js:
        script = step["with"]["script"]
        print("async function main(core, github, context) {")
        print(script)
        print("}\nmodule.exports = main;")
        return

    script = step["run"]
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(action_file)))
    lib_path = os.path.join(repo_root, "scripts", "lib.sh")
    script = script.replace(
        '"${{ github.action_path }}/../scripts/lib.sh"',
        f'"{lib_path}"',
    )
    print("#!/usr/bin/env bash")
    print(script)


if __name__ == "__main__":
    main()
