#!/bin/sh
# Stored in /var/local, available even while /mnt/us is exported over USB.
exec >> /var/local/kindle-desk/bootstrap.log 2>&1
echo "Bootstrap $(date)"
# Do not change USB gadget mode during native GUI startup.
sleep 10
i=0
until [ -f /mnt/us/kindle-desk/run.sh ] && [ -x /mnt/us/kindle-desk/bin/ble-client ]; do
  i=$((i+1))
  # Leave the stock UI available if the dashboard assets cannot be mounted.
  [ "$i" -lt 30 ] || exit 0
  sleep 1
done
if [ -e /mnt/us/kindle-desk/restore-reader ]; then
  rm -f /var/local/kindle-desk/enabled
  exit 0
fi
exec /bin/sh /mnt/us/kindle-desk/run.sh
