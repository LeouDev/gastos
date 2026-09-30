#!/bin/zsh
# Takes App Store screenshots on a 6.9" simulator and frames them into appstore/screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(xcrun simctl list devices available | grep "gastos 6.9" | grep -oE '[0-9A-F-]{36}' | head -1)
[ -n "$SIM" ] || SIM=$(xcrun simctl create "gastos 6.9" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max)
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcodebuild -project gastos.xcodeproj -scheme gastos -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/dd \
  -parallel-testing-enabled NO test -only-testing:gastosUITests/AppStoreScreenshotsUITests -resultBundlePath build/screenshots.xcresult -quiet
RAW=build/screenshots-raw; rm -rf $RAW; mkdir -p $RAW
xcrun xcresulttool export attachments --path build/screenshots.xcresult --output-path $RAW
python3 - "$RAW" <<'PY'
import json, sys, os
raw = sys.argv[1]
for t in json.load(open(f"{raw}/manifest.json")):
    for a in t["attachments"]:
        os.rename(f"{raw}/{a['exportedFileName']}", f"{raw}/{a['suggestedHumanReadableName'].split('_')[0]}.png")
PY
python3 scripts/frame_screenshots.py $RAW appstore/screenshots
rm -rf build/screenshots.xcresult
