#!/usr/bin/env bash
# Shared functions. Every script loads it:  source "$(dirname "$0")/../common/lib.sh"

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$_LIB_DIR/.." && pwd)}"

# Load env.sh unless the user already did
if [[ -z "${DX_ENV_LOADED:-}" ]]; then
  if [[ -f "$REPO_ROOT/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/env.sh"
  else
    echo "❌ $REPO_ROOT/env.sh not found. Create it with:  cp env.example.sh env.sh  and edit it" >&2
    echo "   (or generate it with the optional configuration wizard, see README.md)." >&2
    exit 1
  fi
fi

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[1;33mWARN\033[0m  %s\n' "$*"; }
fail() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

# require_vars VAR1 VAR2 ...  -> abort if any is empty (without printing its value)
require_vars() {
  local v missing=()
  for v in "$@"; do [[ -n "${!v:-}" ]] || missing+=("$v"); done
  ((${#missing[@]} == 0)) || die "Missing variables in env.sh: ${missing[*]}"
}

# require_cmd cmd1 cmd2 ...
require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Tool '$c' is not installed on your workstation"; done
}

# apply_secret <ns> <kubectl create secret ... args>  -> create or update idempotently
apply_secret() {
  local ns="$1"; shift
  kubectl -n "$ns" create secret "$@" --dry-run=client -o yaml | kubectl apply -f -
}

# render <template> '<$VAR1 $VAR2>'  -> replace ONLY the listed variables and write to stdout
render() { envsubst "$2" < "$1"; }

is_openshift() { [[ "$PLATFORM" == "openshift" ]]; }

# Helm wait until everything is Ready. Helm 4 changed "--wait": by default it uses the "watcher"
# strategy, which ABORTS as soon as a pod is reported as failed. DX has normal failures while it
# starts (DAM retries until its PostgreSQL is ready), so with Helm 4 we use "--wait=legacy", which,
# like Helm 3, waits up to --timeout for everything to become Ready.
if helm version --short 2>/dev/null | grep -q '^v3'; then HELM_WAIT="--wait"; else HELM_WAIT="--wait=legacy"; fi

# Helm 4 applies the objects with server-side apply: a field changed by another tool (e.g. the MCP server
# list that custom-mcp/03-iq-register.sh patches in the IQ Integrator ConfigMap) makes the next "helm
# upgrade" fail with "conflict with kubectl-patch". --force-conflicts lets Helm take the field back.
# Helm 3 has no such conflicts (and no such option).
if helm version --short 2>/dev/null | grep -q '^v3'; then HELM_FORCE_CONFLICTS=""; else HELM_FORCE_CONFLICTS="--force-conflicts"; fi
