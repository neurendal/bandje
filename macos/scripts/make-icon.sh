#!/bin/sh
# Builds Resources/AppIcon.icns (macOS 15 and the SwiftPM `make` build) from Resources/AppIcon.icon,
# the Icon Composer document shared with the iPhone app (bandje-ios Bandje/AppIcon.icon; copy it
# here when it changes, then run this). The App Store build also compiles the .icon itself (Liquid
# Glass, dark and tinted variants on macOS 26).
set -eu
cd "$(dirname "$0")/.."
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
tmp=$(mktemp -d)
set=$tmp/AppIcon.iconset
mkdir -p "$set"
"$ICTOOL" Resources/AppIcon.icon --export-image --output-file "$tmp/icon_1024.png" \
    --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
cp "$tmp/icon_1024.png" Resources/AppIcon-1024.png
rm -rf "$tmp"
echo "wrote Resources/AppIcon.icns from Resources/AppIcon.icon"
