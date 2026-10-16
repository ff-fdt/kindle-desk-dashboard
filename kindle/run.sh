#!/bin/sh
set -eu
cd /mnt/us/kindle-desk
exec >> runtime.log 2>&1
echo "Kindle Desk starting $(date)"
touch native-settings
# Framework is fully ready here. Arm USB networking before pausing the UI,
# so a later cable attachment cannot export the live runtime's user partition.
sh ./usb-service.sh || true
(
  while :; do
    if [ -e /sys/class/net/usb0 ]; then sh ./usb-service.sh || true; fi
    sleep 5
  done
) &
usb_pid=$!
cleanup() {
  kill "${client_pid:-}" "${display_pid:-}" "${control_pid:-}" "$usb_pid" 2>/dev/null || true
  sh ./ui-mode.sh native || true
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM
(until sh ./ui-mode.sh dashboard; do sleep 3; done) &
display_pid=$!
lipc-set-prop com.lab126.powerd preventScreenSaver 1 || true
sh ./control.sh &
control_pid=$!
while [ -f /var/local/kindle-desk/enabled ] || [ -f /tmp/kindle-desk-manual ]; do
  ./bin/ble-client &
  client_pid=$!
  wait "$client_pid" || true
  client_pid=''
  # A missing Mac is expected; retain the last frame and reconnect quietly.
  sleep 3
done
