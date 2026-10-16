#!/bin/sh
# Root companion. The unprivileged Bluetooth client cannot write /dev/fb0.
set -eu
cd /mnt/us/kindle-desk
FBINK=/mnt/us/libkh/bin/fbink
last=''
while :; do
  if [ -e native-settings ]; then sleep 2; continue; fi
  if [ -f frame.ready ] && [ -f frame.png ]; then
    revision=$(cat frame.ready)
    case "$revision" in *[!0-9a-f]*|'') sleep 2; continue;; esac
    if [ "${#revision}" -eq 16 ] && [ "$revision" != "$last" ]; then
      if "$FBINK" -q -c -w -g file=/mnt/us/kindle-desk/frame.png; then
        printf '%s\n' "$revision" > frame.displayed.tmp
        mv frame.displayed.tmp frame.displayed
        last=$revision
      fi
    fi
  fi
  sleep 2
done
