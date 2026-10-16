#!/bin/sh
# Stored in /var/local so it remains available during USB storage export.
BASE=${KINDLE_DESK_BASE:-/mnt/us/kindle-desk}
LOCAL=${KINDLE_DESK_PERSISTENT:-/var/local/kindle-desk}
MANUAL=${KINDLE_DESK_MANUAL_FLAG:-/tmp/kindle-desk-manual}
exec >> "$LOCAL/bootstrap.log" 2>&1
echo "Bootstrap $(date)"
sleep 10
# USB storage can stay exported for any length of time. Wait for the device
# assets to return while the native framework and USB screen remain usable.
until [ -f "$BASE/run.sh" ] && [ -x "$BASE/bin/ble-client" ]; do
  [ -f "$LOCAL/enabled" ] || [ -f "$MANUAL" ] || exit 0
  sleep 1
done
if [ -e "$BASE/restore-reader" ]; then
  rm -f "$LOCAL/enabled"
  exit 0
fi
exec /bin/sh "$BASE/run.sh"
