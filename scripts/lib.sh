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

# detect_platform resolves the platform for the current windsor context,
# honoring an optional override (skips the `windsor get contexts` lookup
# entirely — useful when the caller already knows the platform, e.g. from its
# own build matrix). Sets DETECTED_CONTEXT and DETECTED_PLATFORM. Fails with
# an actionable message if the context or platform can't be determined.
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
# Factored out of kubeconfig/action.yaml so CI can exercise this exact call
# (real aws-cli, fake cluster, no credentials) to catch a flag typo without
# needing a real cluster.
fetch_eks_kubeconfig() {
  local cluster_name="$1" region="$2" kubeconfig_path="$3"
  aws eks update-kubeconfig --name "$cluster_name" --region "$region" --kubeconfig "$kubeconfig_path"
}

# convert_kubelogin_mode rewrites a kubeconfig's Azure auth-provider entries
# into kubelogin's exec-based auth for the given login mode (e.g.
# workloadidentity). A blank mode is a no-op. Doesn't call out to Azure —
# it only rewrites the file — so this is testable without any credentials.
convert_kubelogin_mode() {
  local kubeconfig_path="$1" mode="$2"
  [ -z "$mode" ] && return 0
  kubelogin convert-kubeconfig -l "$mode" --kubeconfig "$kubeconfig_path"
}

# fetch_aks_kubeconfig writes an AKS cluster's kubeconfig via the Azure CLI,
# then converts it via convert_kubelogin_mode. Writes into a temp file and
# only replaces the real one on success, so az can't merge onto a stale
# current-context, and a failed fetch never leaves the path with no
# kubeconfig at all — mirrors null_resource.kubeconfig in
# core/terraform/cluster/azure-aks. Each step guards its own failure with
# `|| return $?` rather than relying on the caller's `set -e`, so a failed az
# call can't fall through into mv/kubelogin acting on a file that was never
# written — this matters for a caller (like a test) that must suspend
# errexit to inspect this function's own failure output.
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

# fetch_gke_kubeconfig writes a GKE cluster's kubeconfig via gcloud, which
# writes to the path in the caller's own KUBECONFIG env var.
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
