#!/usr/bin/env bash
# Kept for compatibility: the support data collector is now common/collect-support-data.sh
exec "$(dirname "$0")/collect-support-data.sh" "$@"
