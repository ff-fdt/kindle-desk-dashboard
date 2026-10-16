#!/bin/sh
exec > /mnt/us/kindle-desk/recovery.log 2>&1
mv /mnt/us/emergency.sh /mnt/us/kindle-desk/last-recovery.sh
rm -f /var/local/kindle-desk/enabled /mnt/us/DONT_START_FRAMEWORK
stop kindle-desk 2>/dev/null || true
mntroot rw
if [ -f /etc/upstart/kindle-desk.conf ]; then mv /etc/upstart/kindle-desk.conf /var/local/kindle-desk/disabled-upstart.conf; fi
mntroot ro
initctl reload-configuration
lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
start x 2>/dev/null || true
start lab126_gui 2>/dev/null || true
start framework 2>/dev/null || true
sync
echo 'Original reader restored; dashboard autostart disabled'
