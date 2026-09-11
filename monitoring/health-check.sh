#!/usr/bin/env bash
# health-check.sh - polls the local health endpoint and logs the result.
# Installed to /usr/local/bin and run every 5 minutes via cron.
set -euo pipefail

TS="$(date '+%Y-%m-%d %H:%M:%S')"
URL="http://127.0.0.1/health"

RESPONSE="$(curl -fsS --max-time 5 "$URL" 2>/dev/null || echo '')"

if [[ -n "$RESPONSE" ]]; then
    echo "[$TS] OK - $RESPONSE"
else
    echo "[$TS] FAIL - health endpoint unreachable at $URL"
fi