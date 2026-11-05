#!/usr/bin/env bash
# Lab 1B · Check: the push Job finished and DX serves the Script Application.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
JOB="$SCRIPTAPP_RELEASE-hcl-dx-scriptapp-push"
if kubectl -n "$SHARED_NS" wait job/"$JOB" --for=condition=Complete --timeout=5s >/dev/null 2>&1; then
  ok "Job $JOB completed: $(kubectl -n "$SHARED_NS" logs job/"$JOB" -c dxclient | grep -o "OK: .*")"
else
  fail "Job $JOB did not complete: kubectl -n $SHARED_NS logs job/$JOB -c dxclient"
fi
helm -n "$SHARED_NS" status "$SCRIPTAPP_RELEASE" 2>/dev/null | grep -E "^STATUS|^REVISION" | sed 's/^/    /'
