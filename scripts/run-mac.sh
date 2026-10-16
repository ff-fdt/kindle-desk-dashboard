#!/bin/sh
set -eu
BASE=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
: "${KINDLE_DESK_PYTHON:?Set the virtual-environment Python executable}"
: "${KINDLE_DESK_STATE_DIR:?Set the persistent state directory}"
"$KINDLE_DESK_PYTHON" "$BASE/desk.py" --port 8791 &
collector=$!
"$BASE/build/Kindle Desk Bluetooth.app/Contents/MacOS/KindleDeskBluetooth" "$KINDLE_DESK_STATE_DIR" &
bluetooth=$!
cleanup() { kill "$collector" "$bluetooth" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
while kill -0 "$collector" 2>/dev/null && kill -0 "$bluetooth" 2>/dev/null; do sleep 5; done
exit 1
