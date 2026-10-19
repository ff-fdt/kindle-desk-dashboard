#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O mac/PanelRenderer.swift -framework AppKit -framework CoreText -o build/KindleDeskRenderer
