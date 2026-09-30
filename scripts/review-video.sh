#!/bin/zsh
# Records appstore/review-walkthrough.mp4: a fresh install walking through onboarding, the paywall,
# subscribing (local StoreKit test store) and the main features, on a 6.9" simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep "gastos 6.9" | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl uninstall "$SIM" com.leoudev.gastos 2>/dev/null || true
DEST="platform=iOS Simulator,id=$SIM"
xcodebuild -project gastos.xcodeproj -scheme gastos -destination "$DEST" -derivedDataPath build/dd build-for-testing -quiet
# Raw capture goes to the temp folder: the simulator recorder may not write to external volumes.
RAW="${TMPDIR:-/tmp}/gastos-review-raw.mov"; rm -f "$RAW"
START=$(date +%s)
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$RAW" > /dev/null 2>&1 &
REC=$!
sleep 2
# The product unit test sets up and empties the simulator's StoreKit test store first.
xcodebuild -project gastos.xcodeproj -scheme gastos -destination "$DEST" -derivedDataPath build/dd -parallel-testing-enabled NO \
  test-without-building -only-testing:gastosTests/SubscriptionProductTests -only-testing:gastosUITests/ReviewWalkthroughUITests 2>&1 \
  | while IFS= read -r line; do
      case "$line" in *"ReviewWalkthroughUITests testWalkthrough]' started"*) echo $(( $(date +%s) - START )) > build/review-start.txt;; esac
      case "$line" in *"ReviewWalkthroughUITests testWalkthrough]' passed"*) echo $(( $(date +%s) - START )) > build/review-end.txt;; esac
      case "$line" in *"Test Case"*|*"error:"*) echo "$line";; esac
    done
kill -INT $REC 2>/dev/null || true; wait $REC 2>/dev/null || true
[ -s "$RAW" ] || { echo "Recording failed: $RAW is missing"; exit 1; }
SKIP=$(cat build/review-start.txt)
# Stop before the test tears the app down (the home screen would show).
LENGTH=$(( $(cat build/review-end.txt) - SKIP - 4 ))
mkdir -p appstore
avconvert --source "$RAW" --output appstore/review-walkthrough.mp4 --preset PresetHighestQuality --start $SKIP --duration $LENGTH --replace >/dev/null
echo "Saved appstore/review-walkthrough.mp4 (skipped first ${SKIP}s)"
