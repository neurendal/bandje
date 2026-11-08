#!/usr/bin/env bash
# Verifies Bandje cannot use the network.
# Hard checks fail the run (exit 1). Warnings are reported only.
# The real guarantee from M5 on is the App Sandbox without network entitlements.
set -u

cd "$(dirname "$0")/.."
APP="build/Bandje.app"
BIN="$APP/Contents/MacOS/Bandje"
ALLOWED_DEP="desert-ant-core"
fail=0

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

uses_sdk=0
if [ -f Package.swift ] && grep -q "$ALLOWED_DEP" Package.swift; then uses_sdk=1; fi

echo "1/6 Source scan (our code only)"
PATTERN='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWListener|NWBrowser|CFSocket|CFStream|socket\(|getaddrinfo|WKWebView|import WebKit|https?://|SUFeedURL|Sparkle|Firebase|Sentry|Analytics|TelemetryDeck|import ScreenCaptureKit|SCStream|CGWindowList|\.download\(|import CloudKit|CKContainer|CKDatabase|PrivateCloudCompute'
# The only URLs allowed are the three About links (they open the browser; akkoord 2026-11-05).
ABOUT_LINKS='^Sources/Bandje/About\.swift:[0-9]+:.*URL\(string: "https://((neurendal|desertant)\.com|band\.je)"\)!$'
# The shared web page (WebExport.swift) links to band.je, and only there (owner, 2026-11-06).
EXPORT_LINK='^Sources/Bandje/WebExport\.swift:[0-9]+:.*"https://band\.je/?"'
# The SVG namespace in the icon's layers (Resources/AppIcon.icon) is an identifier, not a link: it is
# blanked before the second match, so any other URL on such a line still fails.
if grep -rnE "$PATTERN|PrivateCloudComputeLanguageModel" Sources Resources 2>/dev/null | grep -vE '^\S+:[0-9]+:\s*//' | grep -vE "$ABOUT_LINKS" | grep -vE "$EXPORT_LINK" \
   | sed -E 's#(xmlns="http://www\.w3\.org/2000/svg")##' | grep -E "$PATTERN|PrivateCloudComputeLanguageModel"; then
  red "  Forbidden API, URL or download call in our code (see above)"; fail=1
else
  green "  Clean"
fi

echo "2/6 Package dependencies"
if [ -f Package.swift ]; then
  deps=$(grep -nE '\.package\(' Package.swift || true)
  if [ -z "$deps" ]; then
    green "  None"
  else
    other=$(echo "$deps" | grep -v "$ALLOWED_DEP" || true)
    if [ -n "$other" ]; then
      red "  Dependency other than $ALLOWED_DEP:"; echo "$other"; fail=1
    fi
    sdk=$(echo "$deps" | grep "$ALLOWED_DEP" || true)
    if [ -n "$sdk" ]; then
      if echo "$sdk" | grep -q 'exact:'; then
        green "  $ALLOWED_DEP pinned with exact:"
      else
        red "  $ALLOWED_DEP not pinned with exact:"; echo "$sdk"; fail=1
      fi
    fi
  fi
  # Resolved graph: only the SDK and the one package its Who product pulls in (apple/swift-numerics).
  if [ -f Package.resolved ]; then
    resolved=$(grep -oE '"identity" *: *"[^"]+"' Package.resolved | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)
    unexpected=$(echo "$resolved" | grep -vxE "$ALLOWED_DEP|swift-numerics" || true)
    if [ -n "$unexpected" ]; then
      red "  Package.resolved contains unexpected packages:"; echo "$unexpected"; fail=1
    else
      green "  Package.resolved: $(echo $resolved)"
    fi
  fi
fi

if [ ! -d "$APP" ]; then
  red "3-6 skipped: $APP not found, run 'make app' first"; exit 1
fi

echo "3/6 Entitlements"
# network.client is only for the Desert Ant Labs SDK license check (Makefile); never network.server.
ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
if echo "$ENT" | grep -q 'com.apple.security.network.server'; then
  red "  network.server present: never allowed"; fail=1
elif echo "$ENT" | grep -q 'com.apple.security.network.client'; then
  yellow "  network.client, only for the SDK license check (our code is scanned in 1/6)"
else
  green "  No network entitlement"
fi

# iCloud: only iCloud Documents (iCloud Drive, opt-in sync), never CloudKit (CLAUDE.md, limit 8).
if echo "$ENT" | grep -A3 'com.apple.developer.icloud-services' | grep -q 'CloudKit'; then
  red "  iCloud service CloudKit present: only CloudDocuments is allowed"; fail=1
elif echo "$ENT" | grep -q 'com.apple.developer.icloud-services'; then
  yellow "  iCloud Documents (opt-in iCloud Drive sync; macOS syncs the files, not our code)"
fi

echo "4/6 Sandbox"
if echo "$ENT" | grep -q 'com.apple.security.app-sandbox'; then
  green "  ON"
elif [ $uses_sdk -eq 1 ]; then
  red "  OFF while $ALLOWED_DEP is linked: not allowed (the SDK requires the sandbox)"; fail=1
else
  yellow "  OFF (allowed only without the SDK)"
fi

echo "5/6 Linked frameworks"
if otool -L "$BIN" | grep -E 'Network\.framework|WebKit|ScreenCaptureKit|Sparkle|CloudKit'; then
  red "  Forbidden framework linked"; fail=1
else
  green "  Clean"
fi

echo "6/6 URL strings in binary (warning only)"
urls=$(strings -a "$BIN" | grep -oE 'https?://[^ "]+' | grep -vE 'apple\.com/(DTDs|dtds)|www\.w3\.org' | sort -u || true)
if [ -n "$urls" ]; then
  yellow "  Found (from the SDK: license check, and a downloader Bandje never calls):"
  echo "$urls" | sed 's/^/    /'
else
  green "  None"
fi

echo
if [ $fail -eq 0 ]; then green "PASS"; else red "FAIL"; fi
exit $fail
