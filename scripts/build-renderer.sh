#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swift build --package-path mac --scratch-path "$PWD/build/swift" -c release --product KindleDeskRenderer
BIN=$(swift build --package-path mac --scratch-path "$PWD/build/swift" -c release --show-bin-path)
cp "$BIN/KindleDeskRenderer" build/KindleDeskRenderer
# SwiftPM's resource bundle must travel with the standalone executable.
for bundle in "$BIN"/*.bundle; do
  [ -d "$bundle" ] || continue
  rm -rf "build/$(basename "$bundle")"
  cp -R "$bundle" build/
done
