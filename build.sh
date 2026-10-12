#!/bin/sh
set -e
cd "$(dirname "$0")"

# Universal binary: Apple Silicon and Intel.
swift build -c release --arch arm64 --arch x86_64

APP=ACBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/apple/Products/Release/ACBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
