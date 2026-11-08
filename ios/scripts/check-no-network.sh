#!/usr/bin/env bash
# Verifies Bandje for iOS's own code cannot use the network (CLAUDE.md, hard limit 1).
# Scans only our sources, not the SDK. The Desert Ant Labs SDK license check must keep working:
# this script also FAILS if anything would block it (ATS keys, network filters).
# Hard checks fail the run (exit 1). Warnings are reported only.
set -u

cd "$(dirname "$0")/.."
ALLOWED_DEP="desert-ant-core"
SOURCES="Bandje ShareExtension Widgets Shared"
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Bandje.app"
BIN="$APP/Bandje"
RESOLVED="Bandje.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
fail=0

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

dirs=""
for d in $SOURCES; do [ -d "$d" ] && dirs="$dirs $d"; done

echo "1/6 Source scan (our code only:$dirs)"
PATTERN='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWListener|NWBrowser|NEFilter|NetworkExtension|CFSocket|CFStream|socket\(|getaddrinfo|WKWebView|import WebKit|SFSafariViewController|https?://|Sparkle|Firebase|Sentry|Analytics|TelemetryDeck|Crashlytics|CloudKit|NSUbiquitousKeyValueStore|\.download\(|PrivateCloudCompute'
# The only URLs allowed: the three About links (they open the browser) and the DAL attribution URL.
# Plus the plist DTD header (not a network call).
ALLOWED_LINES='https://((www\.)?(neurendal|desertant)\.com|band\.je)(/[a-z/]*)?"?|http://www\.apple\.com/DTDs/PropertyList-1\.0\.dtd'
hits=$(grep -rnE "$PATTERN" $dirs --include='*.swift' --include='*.plist' --include='*.xcstrings' --include='*.entitlements' 2>/dev/null \
  | grep -vE '^\S+:[0-9]+:\s*//' || true)
bad=$(echo "$hits" | grep -v '^$' | while IFS= read -r line; do
  stripped=$(echo "$line" | sed -E "s#$ALLOWED_LINES##g")
  if echo "$stripped" | grep -qE "$PATTERN"; then echo "$line"; fi
done)
if [ -n "$bad" ]; then
  echo "$bad"; red "  Forbidden API, URL or download call in our code (see above)"; fail=1
else
  green "  Clean"
fi

echo "2/6 Package dependencies (project.yml)"
pkgs=$(awk '/^packages:/{f=1;next} /^[a-z]/{f=0} f && /^  [A-Za-z0-9_-]+:/{gsub(/[ :]/,""); print}' project.yml)
other=$(echo "$pkgs" | grep -vx "$ALLOWED_DEP" | grep -v '^$' || true)
if [ -n "$other" ]; then red "  Dependency other than $ALLOWED_DEP: $other"; fail=1; fi
if grep -A3 "^  $ALLOWED_DEP:" project.yml | grep -q 'exactVersion: "4.2.3"'; then
  green "  $ALLOWED_DEP pinned exactVersion 4.2.3"
else
  red "  $ALLOWED_DEP not pinned to exactVersion 4.2.3"; fail=1
fi
products=$(grep -E '^\s+product:' project.yml | awk '{print $2}' | sort -u | tr '\n' ' ')
if echo "$products" | grep -qvxE '(Voz |Who |Voz Who )'; then
  red "  Products other than Voz and Who: $products"; fail=1
else
  green "  Products: $products"
fi
if [ -f "$RESOLVED" ]; then
  resolved=$(grep -oE '"identity" *: *"[^"]+"' "$RESOLVED" | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)
  unexpected=$(echo "$resolved" | grep -vxE "$ALLOWED_DEP|swift-numerics" || true)
  if [ -n "$unexpected" ]; then
    red "  Package.resolved contains unexpected packages:"; echo "$unexpected"; fail=1
  else
    green "  Package.resolved: $(echo $resolved)"
  fi
else
  yellow "  $RESOLVED not found (run 'make resolve')"
fi

echo "3/6 App Transport Security / network filters (must not block the SDK license check)"
plists=$(find $dirs -name '*.plist' 2>/dev/null)
if [ -n "$plists" ] && grep -l 'NSAppTransportSecurity\|NSPinnedDomains\|NEFilter' $plists project.yml 2>/dev/null; then
  red "  ATS or filter keys present (neither loosening nor blocking is allowed)"; fail=1
elif grep -q 'NSAppTransportSecurity' project.yml; then
  red "  ATS keys in project.yml"; fail=1
else
  green "  None"
fi

if [ ! -d "$APP" ]; then
  red "4-6 skipped: $APP not found, run 'make build' first"; exit 1
fi

echo "4/6 Entitlements"
ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
# iCloud Drive (opt-in sync, CLAUDE.md hard limit 2) is allowed: only the one container and only
# CloudDocuments. CloudKit and key-value storage are not.
if echo "$ENT" | grep -qE 'networkextension|CloudKit|ubiquity-kvstore'; then
  red "  Network extension, CloudKit or iCloud key-value entitlement present"; fail=1
elif echo "$ENT" | grep -qE 'icloud|ubiquity' && \
     [ "$(echo "$ENT" | grep -oE 'iCloud\.[A-Za-z0-9.]+' | sort -u)" != "iCloud.com.neurendal.bandje" ]; then
  red "  iCloud entitlement for another container than iCloud.com.neurendal.bandje"; fail=1
else
  green "  No network-extension, CloudKit or key-value entitlements (iCloud Drive: own container only)"
fi

echo "5/6 Linked frameworks"
# Debug builds put the code in Bandje.debug.dylib; check whichever binaries exist.
BINS="$BIN"
[ -f "$APP/Bandje.debug.dylib" ] && BINS="$BINS $APP/Bandje.debug.dylib"
for ext in "$APP"/PlugIns/*.appex; do
  [ -d "$ext" ] || continue
  name=$(basename "$ext" .appex)
  [ -f "$ext/$name" ] && BINS="$BINS $ext/$name"
  [ -f "$ext/$name.debug.dylib" ] && BINS="$BINS $ext/$name.debug.dylib"
  if codesign -d --entitlements - --xml "$ext" 2>/dev/null | grep -qE 'networkextension|icloud|ubiquity'; then
    red "  $name: network-extension or iCloud entitlement present"; fail=1
  fi
done
if otool -L $BINS | grep -E 'Network\.framework|WebKit|NetworkExtension|CloudKit|SafariServices'; then
  red "  Forbidden framework linked"; fail=1
else
  green "  Clean"
fi

echo "6/6 URL strings in binary (warning only)"
urls=$(cat $BINS | strings -a | grep -oE 'https?://[^ "]+' | grep -vE 'apple\.com/(DTDs|dtds)|www\.w3\.org' | sort -u || true)
if [ -n "$urls" ]; then
  yellow "  Found (from the SDK: license check, and a downloader Bandje never calls):"
  echo "$urls" | sed 's/^/    /'
else
  green "  None"
fi

echo
if [ $fail -eq 0 ]; then green "PASS"; else red "FAIL"; fi
exit $fail
