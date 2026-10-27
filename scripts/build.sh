#!/bin/sh
# Builds a universal "Peep.app" and build/Peep.zip.
# Usage: scripts/build.sh [version]
set -eu
cd "$(dirname "$0")/.."

version=${1:-0.0.0-dev}
app="build/Peep.app"
flags="-c release --arch arm64 --arch x86_64"

swift build $flags
rm -rf build
mkdir -p "$app/Contents/MacOS"
cp "$(swift build $flags --show-bin-path)/Peep" "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
# ponytail: ad-hoc signature only; Developer ID signing and notarization need an Apple developer account
codesign --force --sign - "$app"
ditto -c -k --keepParent "$app" build/Peep.zip
echo "Built $app and build/Peep.zip"
