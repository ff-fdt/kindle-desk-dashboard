#!/bin/sh
set -eu
BASE=/mnt/us/kindle-desk
if [ ! -e /sys/class/net/usb0 ]; then
  lipc-set-prop -i com.lab126.volumd useUsbForNetwork 1 || exit 0
  lipc-send-event -r 3 -d 2 com.lab126.hal usbUnconfigured || true
  lipc-send-event -r 3 -d 2 com.lab126.hal usbPlugOut || true
fi
i=0
until [ -e /sys/class/net/usb0 ]; do
  i=$((i+1)); [ "$i" -lt 15 ] || exit 0; sleep 1
done
ifconfig usb0 192.168.15.244 netmask 255.255.255.0 up
ifconfig usb0:1 169.254.244.1 netmask 255.255.0.0 up || true
iptables -C INPUT -i usb0 -p tcp --dport 2222 -j ACCEPT 2>/dev/null || iptables -I INPUT -i usb0 -p tcp --dport 2222 -j ACCEPT
if [ -f "$BASE/ssh.pid" ]; then
  pid=$(cat "$BASE/ssh.pid")
  case "$pid" in ''|*[!0-9]*) pid=0;; esac
  if [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null &&
     [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = "$BASE/bin/dropbear" ]; then
    exit 0
  fi
fi
"$BASE/bin/dropbear" -R -s -j -k -P "$BASE/ssh.pid" -p 192.168.15.244:2222 -p 169.254.244.1:2222
