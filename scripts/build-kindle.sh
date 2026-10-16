#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${ZIG:?Set ZIG to the Zig executable}"
: "${KINDLEBT_SOURCE:?Set KINDLEBT_SOURCE to the upstream source tree}"
: "${ACE_INCLUDE:?Set ACE_INCLUDE to the external ACE include directory}"
: "${KINDLEBT_LIB:?Set KINDLEBT_LIB to the upstream runtime directory}"
: "${ACE_LIB_DIR:?Set directory with device libcrypto.so.1.0.0}"
mkdir -p build
# Lazy relocations and the SysV hash retain compatibility with Kindle glibc 2.20.
"$ZIG" cc -target arm-linux-gnueabihf.2.17 -mcpu=cortex_a7 -fPIC -O2 \
  -I "$KINDLEBT_SOURCE/include" -I "$ACE_INCLUDE" kindle/ble-client.c \
  -L "$KINDLEBT_LIB" -L "$ACE_LIB_DIR" -lkindlebt -l:libcrypto.so.1.0.0 -ldl -lpthread \
  -Wl,--allow-shlib-undefined -Wl,-z,lazy -Wl,--hash-style=sysv \
  -Wl,-z,max-page-size=4096 -Wl,-rpath,/mnt/us/kindle-desk/lib \
  -o build/ble-client
