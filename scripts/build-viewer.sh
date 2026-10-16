#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${ZIG:?Set ZIG to the Zig executable}"
mkdir -p build
"$ZIG" cc -target arm-linux-gnueabihf.2.17 -mcpu=cortex_a7 -O2 \
  -Wall -Wextra -Werror kindle/dashboard-viewer.c -ldl \
  -Wl,-z,lazy -Wl,--hash-style=sysv -Wl,-z,max-page-size=4096 \
  -o build/dashboard-viewer
