#!/bin/sh
set -eu
[ "$(id -u)" = 0 ]
BASE=/mnt/us/kindle-desk
test -x "$BASE/bin/ble-client"
test -x "$BASE/bin/dashboard-viewer"
test -f "$BASE/bootstrap.sh"
mkdir -p /var/local/kindle-desk
if [ -f /etc/upstart/kindle-desk.conf ] && [ ! -f /var/local/kindle-desk/previous-upstart.conf ]; then
  cp /etc/upstart/kindle-desk.conf /var/local/kindle-desk/previous-upstart.conf
fi
cp "$BASE/bootstrap.sh" /var/local/kindle-desk/bootstrap.sh
chmod 700 /var/local/kindle-desk/bootstrap.sh
mntroot rw
trap 'mntroot ro' EXIT
cp "$BASE/kindle-desk.conf" /etc/upstart/kindle-desk.conf
mntroot ro
trap - EXIT
rm -f /mnt/us/DONT_START_FRAMEWORK
rm -f /var/local/kindle-desk/enabled
rm -f /tmp/kindle-desk-manual
initctl reload-configuration
stop kindle-desk 2>/dev/null || true
# Leave automatic takeover disabled until manual native/dashboard transitions
# and a controlled cold boot have been qualified on this device.
sync
