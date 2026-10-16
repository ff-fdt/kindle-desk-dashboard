#!/bin/sh
# Invoke only after manual native/dashboard and BLE controls are qualified.
set -eu
[ "$(id -u)" = 0 ]
BASE=/mnt/us/kindle-desk
cmp "$BASE/kindle-desk.conf" /etc/upstart/kindle-desk.conf
test -s "$BASE/frame.png"
test -s "$BASE/frame.displayed"
rm -f "$BASE/restore-reader"
touch /var/local/kindle-desk/enabled
sync
