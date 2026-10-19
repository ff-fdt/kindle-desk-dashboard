#!/bin/sh
set -eu
cd /mnt/us/kindle-desk
exec >> runtime.log 2>&1
echo "Kindle Desk starting $(date)"
touch native-settings
sh ./usb-service.sh || true
(
  while :; do
    if [ -e /sys/class/net/usb0 ]; then sh ./usb-service.sh || true; fi
    sleep 5
  done
) &
usb_pid=$!
viewer_signal() {
  [ -s /tmp/kindle-desk-ui/viewer.ready ] || return 0
  read -r viewer_pid < /tmp/kindle-desk-ui/viewer.ready
  case "$viewer_pid" in ''|*[!0-9]*) return 0;; esac
  [ "$(readlink "/proc/$viewer_pid/exe" 2>/dev/null)" = /mnt/us/kindle-desk/bin/dashboard-viewer ] || return 0
  kill "-$1" "$viewer_pid" 2>/dev/null || true
}
stop_client() {
  if [ -n "${client_pid:-}" ]; then
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
    client_pid=''
  fi
}
cleanup() {
  stop_client
  kill "${display_pid:-}" "${control_pid:-}" "$usb_pid" 2>/dev/null || true
  viewer_signal CONT
  sh ./ui-mode.sh native || true
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM
(until sh ./ui-mode.sh dashboard; do sleep 3; done) &
display_pid=$!
keep_awake=0
[ ! -f /var/local/kindle-desk/keep-awake ] || keep_awake=1
lipc-set-prop com.lab126.powerd preventScreenSaver "$keep_awake" || true
sh ./control.sh &
control_pid=$!
awake=1
client_pid=''
while [ -f /var/local/kindle-desk/enabled ] || [ -f /tmp/kindle-desk-manual ]; do
  power_state=$(lipc-get-prop com.lab126.powerd state 2>/dev/null) || power_state=''
  case "$power_state" in
    active)
      if [ "$awake" -eq 0 ]; then
        lipc-set-prop com.lab126.powerd preventScreenSaver "$keep_awake" || true
        viewer_signal CONT
        if [ ! -e native-settings ]; then sh ./ui-mode.sh dashboard || true; fi
        awake=1
        echo "Dashboard resumed $(date)"
      fi
      ;;
    screenSaver|readyToSuspend|suspended|screenOff)
      if [ "$awake" -eq 1 ]; then
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
        viewer_signal STOP
        stop_client
        awake=0
        echo "Dashboard sleeping $(date)"
      fi
      ;;
  esac
  if [ "$awake" -eq 1 ]; then
    if [ -z "$client_pid" ] || ! kill -0 "$client_pid" 2>/dev/null; then
      if [ -n "$client_pid" ]; then wait "$client_pid" 2>/dev/null || true; fi
      ./bin/ble-client &
      client_pid=$!
    fi
  fi
  sleep 2
done
