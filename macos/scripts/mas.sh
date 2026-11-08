#!/usr/bin/env bash
# mas.sh: builds Bandje for the Mac App Store with Xcode and exports or uploads it.
#
#   scripts/mas.sh            archive and export a signed .pkg to build/mas/<build>/export (no upload)
#   scripts/mas.sh --upload   archive and upload to App Store Connect (TestFlight, then review)
#   scripts/mas.sh --dev      archive, export development-signed (with iCloud) and install in ~/Applications
#   add --dirty to allow uncommitted changes
#
# Needs: Xcode > Settings > Accounts signed in with the Neurendal B.V. account (team KKWHW59YC3),
# with a role that may create certificates. Xcode creates the App ID, the Apple Distribution and
# Mac Installer Distribution certificates and the Mac App Store profile itself
# (-allowProvisioningUpdates). Uploading also needs the app record in App Store Connect.
# The speech models come from ~/Music/Bandje/.models (scripts/fetch-models.sh), checked against
# models.lock.json.
set -euo pipefail

say() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UPLOAD=0; DIRTY=0; DEV=0
for a in "$@"; do
  case $a in --upload) UPLOAD=1;; --dirty) DIRTY=1;; --dev) DEV=1;; *) die "unknown option $a";; esac
done
if [ $DEV = 1 ] && pgrep -f "$HOME/Applications/Bandje.app/Contents/MacOS/Bandje" >/dev/null; then
  die "Bandje in ~/Applications is running. Quit it first (menu > Quit Bandje)."
fi
[ $DIRTY = 1 ] || [ -z "$(git status --porcelain -- Sources Resources mas Package.swift models.lock.json)" ] \
  || die "Uncommitted changes. Commit first, or use --dirty."

# The build number only has to rise with every upload; a timestamp always does.
BUILD="$(date +%Y%m%d.%H%M)"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
COMMIT="$(git rev-parse --short HEAD)"
OUT="$ROOT/build/mas/$BUILD"
mkdir -p "$OUT"

say "Checks"
make test >/dev/null || die "make test fails, no build."
./scripts/check-no-network.sh >/dev/null || die "check-no-network fails, no build."

say "Info.plist $VERSION ($BUILD), project"
cp Resources/Info.plist build/mas/Info.plist
plutil -replace CFBundleVersion -string "$BUILD" build/mas/Info.plist
xcodegen generate --spec mas/project.yml --quiet

say "Archive (commit $COMMIT)"
# The iCloud entitlement needs a provisioning profile for every signature: the archive is signed for
# development (this Mac must be registered with the team; -allowProvisioningDeviceRegistration does
# that the first time), the export re-signs it for the App Store or for development (--dev).
SIGN=(-allowProvisioningDeviceRegistration)
xcodebuild archive \
  -project mas/Bandje.xcodeproj -scheme Bandje -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/Bandje.xcarchive" \
  -allowProvisioningUpdates "${SIGN[@]}" ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  | xcbeautify --quiet

APP="$OUT/Bandje.xcarchive/Products/Applications/Bandje.app"
say "Release checks on the archived app"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q network.server && die "network.server present"
for s in --selftest --probe-permissions FakeMic PermissionProbe; do
  strings -a "$APP/Contents/MacOS/Bandje" | grep -q -- "$s" && die "DEBUG test hook '$s' in the release binary"
done
[ -f "$APP/Contents/Resources/Models/voz/meta.json" ] || die "models missing in the app"

DEST=export; [ $UPLOAD = 1 ] && DEST=upload
METHOD=app-store-connect; [ $DEV = 1 ] && METHOD=debugging
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
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
  -exportPath "$OUT/export" -allowProvisioningUpdates | xcbeautify --quiet

if [ $DEV = 1 ]; then
  # A development-signed copy with the iCloud entitlement, to test sync on this Mac.
  rm -rf "$HOME/Applications/Bandje.app"
  ditto "$OUT/export/Bandje.app" "$HOME/Applications/Bandje.app"
  say "Installed ~/Applications/Bandje.app (development signed, iCloud), $VERSION ($BUILD), commit $COMMIT"
elif [ $UPLOAD = 1 ]; then
  # Which code is in which TestFlight build: a tag per upload.
  git tag "build/$BUILD" "$COMMIT" 2>/dev/null || true
  say "Uploaded: Bandje $VERSION ($BUILD), commit $COMMIT. App Store Connect processes it in 5-30 minutes."
else
  say "Exported: $OUT/export (Bandje $VERSION ($BUILD), commit $COMMIT). Upload with Transporter or --upload."
fi
