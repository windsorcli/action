#!/usr/bin/env bash
# Wraps kubelogin for Azure workload identity in CI. The cloud-auth action
# installs this file as `kubelogin` ahead of the real binary on PATH.
#
# For `get-token`, it writes a fresh GitHub OIDC token to the federated-token
# file, because the token expires after about 5 minutes. Other calls, such as
# `--version`, run without a fetch so they stay inside caller time limits.
# Every call then passes all arguments, unchanged, to the real kubelogin.
#
# Required env: KUBELOGIN_SHIM_REAL, AZURE_FEDERATED_TOKEN_FILE,
# KUBELOGIN_SHIM_LOG. For get-token, also ACTIONS_ID_TOKEN_REQUEST_TOKEN and
# ACTIONS_ID_TOKEN_REQUEST_URL (the job needs `permissions: id-token: write`).
set -euo pipefail

: "${KUBELOGIN_SHIM_REAL:?}" "${AZURE_FEDERATED_TOKEN_FILE:?}" "${KUBELOGIN_SHIM_LOG:?}"

log() { echo "$*" >> "$KUBELOGIN_SHIM_LOG"; }

log "=== $(date -u +%FT%TZ) invoked, args: $* ==="

if [ "${1:-}" = "get-token" ]; then
  tmp="$(mktemp "${AZURE_FEDERATED_TOKEN_FILE}.XXXXXX")"
  if ! curl -fsSL --max-time 10 --retry 3 --retry-all-errors --retry-delay 1 \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?}" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL:?}&audience=api://AzureADTokenExchange" \
      | jq -r '.value // empty' > "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    log "federated token fetch failed"
    echo "::error::kubelogin shim: could not fetch a federated token from GitHub's OIDC endpoint. The job needs 'permissions: id-token: write'." >&2
    exit 1
  fi
  mv -f "$tmp" "$AZURE_FEDERATED_TOKEN_FILE"
  log "federated token OK, file bytes: $(wc -c < "$AZURE_FEDERATED_TOKEN_FILE")"
fi

exec "$KUBELOGIN_SHIM_REAL" "$@"
