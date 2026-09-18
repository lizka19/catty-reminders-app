#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/home/password_123/Desktop/Catty/catty-reminders-app"
PYTHON="$APP_DIR/venv/bin/python"
RELEASES_DIR="$APP_DIR/.deploy/releases"
APP_LOG="$APP_DIR/app.log"

PUSHED_REF="${1:-}"
DEPLOY_SHA="${2:-}"

if [[ ! "$PUSHED_REF" =~ ^refs/heads/ ]]; then
    echo "Unsupported Git ref: $PUSHED_REF" >&2
    exit 1
fi

if [[ ! "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Invalid commit SHA: $DEPLOY_SHA" >&2
    exit 1
fi

if [[ ! -x "$PYTHON" ]]; then
    echo "Python virtual environment not found: $PYTHON" >&2
    exit 1
fi

cd "$APP_DIR"
mkdir -p "$RELEASES_DIR"

echo "Fetching $PUSHED_REF..."
git fetch --force origin "$PUSHED_REF"

FETCHED_SHA="$(git rev-parse 'FETCH_HEAD^{commit}')"
if [[ "$FETCHED_SHA" != "$DEPLOY_SHA" ]]; then
    echo "Fetched SHA $FETCHED_SHA does not match webhook SHA $DEPLOY_SHA" >&2
    exit 1
fi

RELEASE_DIR="$RELEASES_DIR/$DEPLOY_SHA"
if [[ ! -d "$RELEASE_DIR" ]]; then
    mkdir -p "$RELEASE_DIR"
    git archive "$DEPLOY_SHA" | tar -x -C "$RELEASE_DIR"
fi

echo "Running unit tests..."
cd "$RELEASE_DIR"
"$PYTHON" -m pytest -q tests/test_unit.py || true

echo "Stopping the previous application process..."
pkill -f '[u]vicorn app\.main:app' 2>/dev/null || true

echo "Starting Catty from commit $DEPLOY_SHA..."

DEPLOY_REF="$DEPLOY_SHA" nohup "$PYTHON" -m uvicorn app.main:app \
    --host 0.0.0.0 \
    --port 8181 \
    > "$APP_LOG" 2>&1 < /dev/null &

NEW_PID=$!

for _ in {1..30}; do
    if ! kill -0 "$NEW_PID" 2>/dev/null; then
        echo "Application process exited unexpectedly" >&2
        tail -n 50 "$APP_LOG" >&2 || true
        exit 1
    fi

    PAGE="$(curl --silent --fail --location \
        "http://127.0.0.1:8181/login" || true)"

    if [[ "$PAGE" == *"content=\"$DEPLOY_SHA\""* ]]; then
        echo "Deploy completed: $DEPLOY_SHA"
        exit 0
    fi

    sleep 1
done

echo "Application did not become ready in 30 seconds" >&2
tail -n 50 "$APP_LOG" >&2 || true
exit 1
