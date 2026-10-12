#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release

APP=ACBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ACBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
