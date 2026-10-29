#!/bin/bash
# Builds a universal "Unblock Eject.app" (Apple silicon and Intel) into ./build and signs it, plus
# the unblock-eject command line tool next to it.
#
#   scripts/build-app.sh            ad-hoc signature, for running on this Mac
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:--}"
# A Developer ID build needs a secure timestamp to be notarized; an ad-hoc one can't have one.
timestamp="--timestamp=none"
if [[ "$identity" != "-" ]]; then
	timestamp="--timestamp"
fi
app="build/Unblock Eject.app"

# Each architecture is built on its own and then combined, which works with just the
# Command Line Tools. Building both in one step needs Xcode.
binaries=()
tools=()
for arch in arm64 x86_64; do
	triple="$arch-apple-macosx14.0"
	swift build -c release --product UnblockEject --triple "$triple"
	swift build -c release --product unblock-eject --triple "$triple"
	bin="$(swift build -c release --triple "$triple" --show-bin-path)"
	binaries+=("$bin/UnblockEject")
	tools+=("$bin/unblock-eject")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/UnblockEject"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
	cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi

# No entitlements at all: the app isn't sandboxed, because the sandbox hides other apps' open
# files (see SECURITY.md), and it needs no permission from macOS. The hardened runtime keeps
# other code from being loaded into it. Signed with the default requirement, which names this
# exact build, so nothing else can pass itself off as Unblock Eject.
codesign --force --options runtime "$timestamp" --sign "$identity" "$app"
codesign --verify --strict "$app"

# The command line tool runs as you, in your terminal. It only looks, and never quits or ejects.
lipo -create "${tools[@]}" -output build/unblock-eject
codesign --force --options runtime "$timestamp" --identifier com.stanczykwyatt.unblock-eject \
	--sign "$identity" build/unblock-eject
codesign --verify --strict build/unblock-eject

echo "Built $app and build/unblock-eject"
