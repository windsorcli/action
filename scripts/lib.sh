#!/usr/bin/env bash
# Shared helpers for windsorcli/action's lifecycle sub-actions (up, apply,
# destroy, bootstrap, check). Sourced, not executed directly — every function
# here assumes `set -eo pipefail` is already active in the caller.

# require_windsor fails fast with an actionable message when the windsor CLI
# isn't on PATH. The lifecycle sub-actions don't install the CLI themselves —
# that logic (version resolution, release download vs. build-from-source)
# lives once in the root action, and every sub-action assumes it already ran.
require_windsor() {
  if ! command -v windsor >/dev/null 2>&1; then
    echo "::error::windsor CLI not found on PATH. Run windsorcli/action (the root action, optionally with install-only: true) before this step." >&2
    exit 1
  fi
}

# resolve_workdir cds into $1, joining a relative path onto GITHUB_WORKSPACE
# the same way the root action's workdir input does. A blank argument is a
# no-op (stay in the current directory).
resolve_workdir() {
  local workdir="$1"
  if [ -z "$workdir" ]; then
    return 0
  fi
  case "$workdir" in
    /*) cd "$workdir" || { echo "::error::workdir does not exist: $workdir" >&2; exit 1; } ;;
    *) cd "$GITHUB_WORKSPACE/$workdir" || { echo "::error::workdir does not exist: $GITHUB_WORKSPACE/$workdir" >&2; exit 1; } ;;
  esac
}

# collect_set_flags splits a newline-separated string of key=value pairs into
# repeated `--set key=value` arguments, populating the SET_ARGS array (declare
# it in the caller before invoking this — bash arrays don't survive a
# function return by value). Blank lines are ignored so a trailing newline in
# a multiline workflow input doesn't produce a stray `--set`.
collect_set_flags() {
  local raw="$1"
  SET_ARGS=()
  [ -z "$raw" ] && return 0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    SET_ARGS+=(--set "$line")
  done <<< "$raw"
}

# emit_context_output writes the current windsor context to GITHUB_OUTPUT as
# `context`, so a workflow can key an artifact name or log line off it without
# an extra `windsor get context` step. Best-effort: a context read failure
# (e.g. `check` ran before any `windsor init`) is swallowed rather than
# failing a step whose real work already succeeded.
emit_context_output() {
  local ctx
  ctx=$(windsor get context 2>/dev/null || true)
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "context=$ctx" >> "$GITHUB_OUTPUT"
  fi
}
