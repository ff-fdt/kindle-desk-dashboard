#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${ZIG:?Set ZIG}"
: "${KINDLEBT_SOURCE:?Set upstream source at 59e1d8e69a52e3cd58cee6fcc416d1774ad55791}"
: "${LOGC_SOURCE:?Set log.c source at f9ea34994bd58ed342d2245cd4110bb5c6790153}"
: "${ACE_INCLUDE:?Set external ACE includes}"
: "${ACE_LIB_DIR:?Set directory with device libace_bt.so}"
mkdir -p build
"$ZIG" cc -target arm-linux-gnueabihf.2.17 -mcpu=cortex_a7 -O2 -shared -fPIC \
  -I "$KINDLEBT_SOURCE/include" -I "$LOGC_SOURCE/src" -I "$ACE_INCLUDE" \
  "$KINDLEBT_SOURCE/src/kindlebt.c" "$KINDLEBT_SOURCE/src/kindlebt_log.c" \
  "$KINDLEBT_SOURCE/src/compat_ace.c" "$KINDLEBT_SOURCE/src/compat_ace_implementations.c" \
  "$KINDLEBT_SOURCE/src/compat_ace_shims.c" "$KINDLEBT_SOURCE/src/compat_ace_utils.c" \
  "$KINDLEBT_SOURCE/src/compat_ace_handler.c" "$KINDLEBT_SOURCE/src/compat_acealloc.c" \
  "$LOGC_SOURCE/src/log.c" -L "$ACE_LIB_DIR" -lace_bt -ldl -lpthread \
  -Wl,--allow-shlib-undefined -Wl,-soname,libkindlebt.so -Wl,-z,lazy \
  -Wl,--hash-style=sysv -Wl,-z,max-page-size=4096 -o build/libkindlebt.so
