#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Verifies BandjeKit (bandje-core) cannot use the network. Both apps' scripts/check-no-network.sh run
# this one too. Shared code gets no exceptions: no URLs at all, no dependencies at all.
set -u
cd "$(dirname "$0")/.."
fail=0
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

echo "core 1/2 Source scan (Sources, Tests, Package.swift)"
# The union of the Mac and iOS patterns.
PATTERN='URLSession|URLRequest|NSURLConnection|import Network|NWConnection|NWListener|NWBrowser|NEFilter|NetworkExtension|CFSocket|CFStream|socket\(|getaddrinfo|WKWebView|import WebKit|SFSafariViewController|https?://|SUFeedURL|Sparkle|Firebase|Sentry|Analytics|TelemetryDeck|Crashlytics|import ScreenCaptureKit|SCStream|CGWindowList|CloudKit|CKContainer|CKDatabase|NSUbiquitousKeyValueStore|\.download\(|PrivateCloudCompute'
if grep -rnE "$PATTERN" Sources Tests Package.swift 2>/dev/null | grep -vE '^\S+:[0-9]+:\s*//'; then
  red "  Forbidden API, URL or download call in bandje-core (see above)"; fail=1
else
  green "  Clean"
fi

echo "core 2/2 Package dependencies"
if grep -nE '\.package\(' Package.swift; then
  red "  bandje-core must not have package dependencies"; fail=1
else
  green "  None"
fi

if [ $fail -eq 0 ]; then green "core PASS"; else red "core FAIL"; fi
exit $fail
