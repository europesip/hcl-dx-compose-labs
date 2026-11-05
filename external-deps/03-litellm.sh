#!/usr/bin/env bash
# External dependencies · LiteLLM (proxy towards OpenRouter) in the shared namespace.
# The same installation as Lab 3A steps 1-3: secrets, LiteLLM and a test call to the models.
# Needs OPENROUTER_API_KEY in env.sh.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
L3="$REPO_ROOT/lab3-iq-openrouter"
"$L3/01-secrets.sh"
"$L3/02-litellm-install.sh"
"$L3/03-litellm-test.sh"
echo "Ready for Lab 3A step 4 (install IQ)."
