#!/bin/sh
# Name: Kindle Desk Dashboard
# This test session cannot enable automatic takeover on the next boot.
set -eu
[ "$(id -u)" = 0 ]
BASE=/mnt/us/kindle-desk
cmp "$BASE/kindle-desk.conf" /etc/upstart/kindle-desk.conf
rm -f "$BASE/restore-reader"
touch /tmp/kindle-desk-manual
if ! start kindle-desk; then
  rm -f /tmp/kindle-desk-manual
  sh "$BASE/ui-mode.sh" native || true
  exit 1
fi
