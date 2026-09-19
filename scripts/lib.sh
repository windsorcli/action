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

# detect_platform resolves the platform for the current context, honoring an
# optional override. Sets DETECTED_CONTEXT and DETECTED_PLATFORM.
detect_platform() {
  local platform_override="$1"

  DETECTED_CONTEXT=$(windsor get context 2>/dev/null || true)
  if [ -z "$DETECTED_CONTEXT" ]; then
    echo "::error::could not determine the current windsor context ('windsor get context' returned nothing)" >&2
    exit 1
  fi

  if [ -n "$platform_override" ]; then
    DETECTED_PLATFORM="$platform_override"
    return 0
  fi

  # 'windsor get contexts' prints a table: NAME PROVIDER BACKEND CURRENT.
  # Match the context by name (column 1). This is simpler than matching
  # the CURRENT marker column.
  DETECTED_PLATFORM=$(windsor get contexts 2>/dev/null | awk -v ctx="$DETECTED_CONTEXT" '$1 == ctx { print $2; exit }')
  if [ -z "$DETECTED_PLATFORM" ]; then
    echo "::error::could not determine the platform for context '$DETECTED_CONTEXT' from 'windsor get contexts'. Pass the platform input to skip detection." >&2
    exit 1
  fi
}

# fetch_eks_kubeconfig writes an EKS cluster's kubeconfig via the AWS CLI.
fetch_eks_kubeconfig() {
  local cluster_name="$1" region="$2" kubeconfig_path="$3"
  aws eks update-kubeconfig --name "$cluster_name" --region "$region" --kubeconfig "$kubeconfig_path"
}

# convert_kubelogin_mode rewrites a kubeconfig's Azure auth-provider entries
# to kubelogin's exec-based auth for the given mode. A blank mode is a no-op.
convert_kubelogin_mode() {
  local kubeconfig_path="$1" mode="$2"
  [ -z "$mode" ] && return 0
  kubelogin convert-kubeconfig -l "$mode" --kubeconfig "$kubeconfig_path"
}

# fetch_aks_kubeconfig writes an AKS cluster's kubeconfig via the Azure CLI,
# then converts it via convert_kubelogin_mode. Writes to a temp file first,
# then moves it into place, so a failed fetch never leaves a corrupt or
# missing kubeconfig. Each step returns on its own failure instead of
# relying on the caller's `set -e`.
fetch_aks_kubeconfig() {
  local resource_group="$1" cluster_name="$2" kubeconfig_path="$3" kubelogin_mode="$4"
  local tmp
  tmp="$(mktemp)"
  rm -f "$tmp"
  az aks get-credentials \
    --resource-group "$resource_group" \
    --name "$cluster_name" \
    --file "$tmp" \
    --only-show-errors || return $?
  mv -f "$tmp" "$kubeconfig_path" || return $?
  convert_kubelogin_mode "$kubeconfig_path" "$kubelogin_mode"
}

# fetch_gke_kubeconfig writes a GKE cluster's kubeconfig via gcloud, using
# KUBECONFIG from the environment.
fetch_gke_kubeconfig() {
  local cluster_name="$1" region="$2" project_id="$3"
  gcloud container clusters get-credentials "$cluster_name" --region "$region" --project "$project_id"
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

# discover_contexts populates the parallel arrays CONTEXT_NAMES and
# CONTEXT_PLATFORMS from every contexts/<name>/ directory in the current
# directory. Platform is read from the top-level `platform:` key in each
# context's values.yaml (falling back to the older `provider:` key) via a
# plain-text extraction — this only handles a simple scalar mapping, not
# YAML anchors or nested overrides. Uses parallel indexed arrays rather
# than an associative array, since macOS runners' `shell: bash` can still
# resolve to bash 3.2, which has no associative arrays.
discover_contexts() {
  CONTEXT_NAMES=()
  CONTEXT_PLATFORMS=()
  [ -d contexts ] || return 0

  local dir name values_file platform
  for dir in contexts/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    values_file="${dir}values.yaml"
    platform=""
    if [ -f "$values_file" ]; then
      platform=$(grep -m1 -E '^(platform|provider):' "$values_file" \
        | sed -E 's/^(platform|provider):[[:space:]]*//' \
        | sed -E 's/[[:space:]]*#.*$//' \
        | sed -E "s/^['\"]//; s/['\"]\$//")
    fi
    CONTEXT_NAMES+=("$name")
    CONTEXT_PLATFORMS+=("$platform")
  done
}

# platform_for_context prints the platform recorded for $1 in the arrays
# discover_contexts populated. Fails if $1 isn't a known context.
platform_for_context() {
  local want="$1" i
  for i in "${!CONTEXT_NAMES[@]}"; do
    if [ "${CONTEXT_NAMES[$i]}" = "$want" ]; then
      printf '%s' "${CONTEXT_PLATFORMS[$i]}"
      return 0
    fi
  done
  return 1
}

# require_diffable_ref fails fast if $1 can't be resolved, or shares no
# merge base with HEAD (e.g. an over-shallow checkout) — both would
# otherwise make a later `git diff` silently report no changes, which for
# a build matrix is a false negative: a context that should run, silently
# skipped, rather than a build that's merely slower than necessary.
require_diffable_ref() {
  local ref="$1"
  if ! git rev-parse --verify --quiet "$ref" >/dev/null; then
    echo "::error::changed-since ref '$ref' does not resolve. Check the ref, and that the checkout fetched it (actions/checkout's default shallow clone often won't)." >&2
    exit 1
  fi
  if ! git merge-base "$ref" HEAD >/dev/null 2>&1; then
    echo "::error::no merge base between '$ref' and HEAD — the checkout is probably too shallow. Use actions/checkout with fetch-depth: 0 (or enough depth to reach '$ref')." >&2
    exit 1
  fi
}

# changed_context_names prints, one per line, the names of contexts whose
# own contexts/<name>/ directory has a changed file since $1 (a git ref
# already validated by require_diffable_ref).
changed_context_names() {
  local base_ref="$1"
  git diff --relative --name-only "${base_ref}...HEAD" -- contexts/ \
    | cut -d/ -f2 \
    | sort -u
}

# any_watch_path_changed exits 0 if any file changed since $1 (a git ref
# already validated by require_diffable_ref) starts with one of the
# newline-separated path prefixes in $2. A blank $2 always exits 1.
any_watch_path_changed() {
  local base_ref="$1" watch_paths="$2"
  [ -z "$watch_paths" ] && return 1

  local changed_files file prefix
  changed_files=$(git diff --relative --name-only "${base_ref}...HEAD")
  [ -z "$changed_files" ] && return 1

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      case "$file" in
        "$prefix"*) return 0 ;;
      esac
    done <<< "$watch_paths"
  done <<< "$changed_files"
  return 1
}

# json_escape backslash-escapes backslashes and double quotes in $1, for
# safe embedding in a hand-built JSON string.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# build_matrix_json prints a GitHub Actions matrix object
# ({"include":[{"context":...,"platform":...}, ...]}) from $1, a
# newline-separated list of "name<TAB>platform" pairs. An empty $1
# produces an empty include list, not an error — the caller decides
# whether a zero-entry matrix is fine (GitHub Actions runs zero jobs for
# it) or worth failing on explicitly.
build_matrix_json() {
  local pairs="$1"
  local json='{"include":[' first=true name platform
  while IFS=$'\t' read -r name platform; do
    [ -z "$name" ] && continue
    $first || json+=","
    first=false
    json+="{\"context\":\"$(json_escape "$name")\",\"platform\":\"$(json_escape "$platform")\"}"
  done <<< "$pairs"
  json+="]}"
  printf '%s' "$json"
}
