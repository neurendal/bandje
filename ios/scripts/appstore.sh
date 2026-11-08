#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# appstore.sh: archives Band·je for iPhone and iPad (Release) and exports or uploads it to App Store
# Connect, as the Mac repo's scripts/mas.sh does. Signing through the Xcode account (automatic).
#   scripts/appstore.sh            archive and export an .ipa to build/appstore/<build>/export
#   scripts/appstore.sh --upload   archive and upload (TestFlight; submitting for review stays manual)
set -euo pipefail
cd "$(dirname "$0")/.."
UPLOAD=0
for a in "$@"; do case $a in --upload) UPLOAD=1;; *) echo "unknown option $a" >&2; exit 2;; esac; done
say() { printf '\n== %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

[ -z "$(git status --porcelain -- Bandje Shared Widgets ShareExtension project.yml models.lock.json)" ] \
  || die "Uncommitted changes. Commit first."

# The build number only has to rise with every upload; a timestamp always does (as on the Mac).
BUILD="$(date +%Y%m%d.%H%M)"
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
COMMIT="$(git rev-parse --short HEAD)"
OUT="$PWD/build/appstore/$BUILD"
mkdir -p "$OUT"

say "Checks"
./scripts/check-no-network.sh >/dev/null || die "check-no-network fails, no build."
python3 scripts/verify-and-copy-models.py verify "$HOME/Music/Bandje/.models" >/dev/null || die "models source incomplete"

say "Archive $VERSION ($BUILD), commit $COMMIT"
xcodegen generate --quiet
xcodebuild archive -quiet \
  -project Bandje.xcodeproj -scheme Bandje -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Bandje.xcarchive" \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD"

APP="$OUT/Bandje.xcarchive/Products/Applications/Bandje.app"
say "Release checks on the archived app"
for s in --selftest --demo-state --fake-mic --canned-summary Selftest; do
  strings -a "$APP/Bandje" | grep -q -- "$s" && die "DEBUG test hook '$s' in the release binary"
done
python3 scripts/verify-and-copy-models.py verify "$APP/Models" >/dev/null || die "models missing or wrong in the app"
[ "$(plutil -extract CFBundleVersion raw "$APP/Info.plist")" = "$BUILD" ] || die "build number not set"
ls -d "$APP"/*.lproj | sed 's|.*/||' | tr '\n' ' '; echo

DEST=export; [ $UPLOAD = 1 ] && DEST=upload
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>KKWHW59YC3</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

say "Export ($DEST)"
xcodebuild -exportArchive -archivePath "$OUT/Bandje.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates

if [ $UPLOAD = 1 ]; then
  git tag "ios-build/$BUILD" "$COMMIT" 2>/dev/null || true
  say "Uploaded: Band·je $VERSION ($BUILD), commit $COMMIT. App Store Connect processes it in 5-30 minutes."
else
  say "Exported: $OUT/export (Band·je $VERSION ($BUILD), commit $COMMIT). Upload with --upload or Transporter."
fi
