#!/usr/bin/env bash
set -euo pipefail

LOG="linko.out.log"
: > "$LOG"

# Start server in background and append logs
nohup sh -c 'go run . 2>&1 | tee -a "$PWD/linko.out.log"' >/dev/null 2>&1 &
SERVER_PID=$!

trap 'echo "Cleaning up..."; kill $SERVER_PID 2>/dev/null || true' EXIT

# Wait for server to be ready (try localhost and 127.0.0.1)
READY_HOST=""
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:8899/ | grep -q '^200$'; then
    READY_HOST="http://localhost:8899"
    break
  fi
  if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8899/ | grep -q '^200$'; then
    READY_HOST="http://127.0.0.1:8899"
    break
  fi
  sleep 0.5
done

if [ -z "$READY_HOST" ]; then
  echo "Server did not become ready within timeout"
  tail -n 200 "$LOG" || true
  exit 1
fi

echo "Server ready at $READY_HOST"

# Perform GET /
echo "-- GET / --"
curl -i "$READY_HOST/" || true

echo "-- POST /admin/shutdown --"
curl -i -X POST "$READY_HOST/admin/shutdown" || true

# Give server a moment to shutdown and flush logs
sleep 1

echo "-- Last lines of $LOG --"
tail -n 200 "$LOG" || true

# Cleanup trap will kill server if still running
