#!/bin/zsh
# Archives gastos and uploads it to App Store Connect for TestFlight.
# Needs: your Apple ID in Xcode → Settings → Accounts, and the app record in App Store Connect.
# Each upload needs a unique build number; the timestamp guarantees that.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=$(date +%Y%m%d%H%M)
rm -rf build/gastos.xcarchive build/export
xcodebuild -project gastos.xcodeproj -scheme gastos -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/gastos.xcarchive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$BUILD archive
if xcodebuild -exportArchive -archivePath build/gastos.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates; then
  echo "Uploaded build $BUILD. It appears in App Store Connect → TestFlight after processing (5–30 min)."
else
  # Command-line signing needs the Apple ID in Xcode's accounts; Organizer handles it interactively.
  echo "Upload from the command line failed; opening the archive in Xcode Organizer (Distribute App → App Store Connect)."
  open build/gastos.xcarchive
fi
