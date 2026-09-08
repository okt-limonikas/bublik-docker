#!/bin/sh
# Wait until every part of the E2E stack a test can touch is actually serving:
# the API, the UI bundle, the log server, and the Celery worker that imports.
#
# Environment:
#   BUBLIK_E2E_API_URL        base URL of the stack (required)
#   BUBLIK_E2E_READY_TIMEOUT  seconds to wait (default 180)
#   CELERY_APP                Celery app name for the ping (required)
#   COMPOSE_FILES             docker compose -f flags used for the exec
set -eu

API_URL="${BUBLIK_E2E_API_URL:?BUBLIK_E2E_API_URL is required}"
TIMEOUT="${BUBLIK_E2E_READY_TIMEOUT:-180}"
COMPOSE_FILES="${COMPOSE_FILES:--f docker-compose.yml -f docker-compose.db.yml}"
REQUEST_TIMEOUT=5

case "$TIMEOUT" in
  '' | *[!0-9]*)
    echo "BUBLIK_E2E_READY_TIMEOUT must be a positive integer" >&2
    exit 2
    ;;
esac
[ "$TIMEOUT" -gt 0 ] || {
  echo "BUBLIK_E2E_READY_TIMEOUT must be a positive integer" >&2
  exit 2
}

# shellcheck disable=SC2086
compose() { docker compose $COMPOSE_FILES "$@"; }

serving() {
  curl --fail --silent --show-error --max-time "$REQUEST_TIMEOUT" \
    "$API_URL$1" >/dev/null 2>&1
}

celery_responding() {
  compose exec -T celery \
    celery -A "${CELERY_APP:?CELERY_APP is required}" inspect ping \
    --timeout "$REQUEST_TIMEOUT" 2>/dev/null | grep -q pong
}

deadline=$(($(date +%s) + TIMEOUT))
while [ "$(date +%s)" -lt "$deadline" ]; do
  ready=1
  for path in /api/v2/ /v2/ /logs/; do
    serving "$path" || ready=0
  done
  if [ "$ready" -eq 1 ] && celery_responding; then
    echo "✅ E2E API, UI, logs, and Celery are ready at $API_URL"
    exit 0
  fi
  sleep 1
done

echo "❌ E2E stack did not become ready within ${TIMEOUT}s at $API_URL" >&2
compose ps --all >&2
compose logs --tail=200 >&2
exit 1
