#!/bin/sh
# Name: KD USB Repair
# DontUseFBInk
# One-shot setup. No boot jobs and no firmware replacement.
set -eu
BASE=/mnt/us/kindle-desk
mkdir -p "$BASE"
exec > "$BASE/usb-setup.log" 2>&1
trap 'rc=$?; if [ "$rc" -ne 0 ]; then /mnt/us/libkh/bin/fbink -m -y 10 -S 3 "USB setup failed. See usb-setup.log" || true; fi' EXIT
id
[ "$(id -u)" = 0 ]
/mnt/us/libkh/bin/fbink -m -y 10 -S 3 'Starting USB maintenance...' || true
cat /usr/sbin/usbnetwork
cat /etc/upstart/usbnetd.conf
cat /etc/upstart/usbnet-autostart.conf
"$BASE/bin/dropbear" -V || true
if [ ! -e /sys/class/net/usb0 ]; then
    lipc-set-prop -i com.lab126.volumd useUsbForNetwork 1
    lipc-send-event -r 3 -d 2 com.lab126.hal usbUnconfigured || true
    lipc-send-event -r 3 -d 2 com.lab126.hal usbPlugOut || true
fi
i=0
until [ -e /sys/class/net/usb0 ]; do
    i=$((i+1)); [ "$i" -lt 15 ] || exit 1; sleep 1
done
ifconfig usb0 192.168.15.244 netmask 255.255.255.0 up
ifconfig usb0:1 169.254.244.1 netmask 255.255.0.0 up || true
iptables -C INPUT -i usb0 -p tcp --dport 2222 -j ACCEPT 2>/dev/null || iptables -I INPUT -i usb0 -p tcp --dport 2222 -j ACCEPT
"$BASE/bin/dropbear" -R -s -j -k -P "$BASE/ssh.pid" -p 192.168.15.244:2222 -p 169.254.244.1:2222
ifconfig usb0
sync
/mnt/us/libkh/bin/fbink -m -y 10 -S 4 'Kindle Desk USB ready. Reconnect USB.'
