#!/bin/sh
# Recovery does not reboot: first prevent another takeover, then restore UI.
set -eu
rm -f /mnt/us/DONT_START_FRAMEWORK
rm -f /var/local/kindle-desk/enabled
rm -f /tmp/kindle-desk-manual
touch /mnt/us/kindle-desk/restore-reader
stop kindle-desk 2>/dev/null || true
if [ -f /etc/upstart/kindle-desk.conf ]; then
  mntroot rw
  trap 'mntroot ro' EXIT
  mv /etc/upstart/kindle-desk.conf /var/local/kindle-desk/disabled-upstart.conf
  mntroot ro
  trap - EXIT
  initctl reload-configuration
fi
start x 2>/dev/null || true
start lab126_gui 2>/dev/null || true
start framework 2>/dev/null || true
if [ -f /mnt/us/kindle-desk/ui-mode.sh ]; then
  sh /mnt/us/kindle-desk/ui-mode.sh native || true
fi
lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
sync
