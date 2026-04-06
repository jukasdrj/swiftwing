#!/usr/bin/env bash
# Zep Memory: Warm cache for swiftwing user at session start
# This is a fire-and-forget hint — doesn't block if it fails

ZEP_API_KEY="${ZEP_API_KEY:-}"
ZEP_API_URL="${ZEP_API_URL:-https://api.getzep.com}"
USER_ID="swiftwing"

if [ -z "$ZEP_API_KEY" ]; then
  exit 0  # Silently skip if no API key
fi

# Warm the cache (non-blocking, best-effort)
curl -s -X POST "${ZEP_API_URL}/api/v2/users/${USER_ID}/warm" \
  -H "Authorization: Api-Key ${ZEP_API_KEY}" \
  -H "Content-Type: application/json" \
  --max-time 3 \
  > /dev/null 2>&1 &

echo "🧠 Zep memory warmed for ${USER_ID}"
