#!/usr/bin/env bash
# Screenshots of the app in the simulator for each demo state, appearance and text size.
# Usage: scripts/dev/screenshots.sh <sim udid> <Bandje.app> [states...]
#   STATES default: empty. APPEARANCES default: "light dark". SIZES default: "large".
#   LANGUAGE default: nl (or en).
#   Output: build/screenshots/<state>-<appearance>-<size>[-en].png
set -euo pipefail
cd "$(dirname "$0")/../.."
SIM=$1; APP=$2; shift 2
STATES=${*:-empty}
APPEARANCES=${APPEARANCES:-light dark}
SIZES=${SIZES:-large}
LANGUAGE=${LANGUAGE:-nl}
if [ "$LANGUAGE" = nl ]; then LOC=(-AppleLanguages "(nl)" -AppleLocale nl_NL); SUFFIX=""
else LOC=(-AppleLanguages "(en)" -AppleLocale en_GB); SUFFIX="-en"; fi
OUT=build/screenshots
mkdir -p "$OUT"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

for size in $SIZES; do
  xcrun simctl ui "$SIM" content_size "$size"
  for appearance in $APPEARANCES; do
    xcrun simctl ui "$SIM" appearance "$appearance"
    for state in $STATES; do
      xcrun simctl terminate "$SIM" com.neurendal.bandje 2>/dev/null || true
      if [ "$state" = empty ]; then
        xcrun simctl launch "$SIM" com.neurendal.bandje --reset "${LOC[@]}" >/dev/null
        sleep 3
      else
        # Wait for the demo to write its result (it generates sample audio first), then settle.
        result="$(xcrun simctl get_app_container "$SIM" com.neurendal.bandje data)/Documents/selftest/last.json"
        rm -f "$result"
        xcrun simctl launch "$SIM" com.neurendal.bandje --reset --demo-state "$state" "${LOC[@]}" >/dev/null
        for _ in $(seq 1 60); do
          if [ -f "$result" ] && grep -q '"demo-state"' "$result"; then break; fi
          sleep 0.5
        done
        sleep "${SETTLE:-2.5}"
      fi
      xcrun simctl io "$SIM" screenshot "$OUT/$state-$appearance-$size$SUFFIX.png" >/dev/null 2>&1
      echo "$OUT/$state-$appearance-$size$SUFFIX.png"
    done
  done
done
xcrun simctl terminate "$SIM" com.neurendal.bandje 2>/dev/null || true
xcrun simctl ui "$SIM" content_size large
xcrun simctl ui "$SIM" appearance light
