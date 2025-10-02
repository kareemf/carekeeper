#!/bin/bash

# build-install-launch.sh
#
# Builds, installs, and launches both iOS and watchOS apps to booted simulators.
#
# Usage: ./scripts/build-install-launch.sh

set -e

echo "🚀 Building and installing CareKeeper apps..."
echo ""

# Find booted simulators
IOS_DEVICE=$(xcrun simctl list devices | grep "iPhone.*Booted" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
WATCH_DEVICE=$(xcrun simctl list devices | grep "Apple Watch.*Booted" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

if [ -z "$IOS_DEVICE" ]; then
    echo "⚠️  No booted iPhone simulator found"
    echo "Please boot an iPhone simulator first"
    exit 1
fi

if [ -z "$WATCH_DEVICE" ]; then
    echo "⚠️  No booted Apple Watch simulator found"
    echo "Skipping watchOS app (will only build and install iOS app)"
    WATCH_DEVICE=""
fi

echo "📱 iOS Simulator: $IOS_DEVICE"
if [ -n "$WATCH_DEVICE" ]; then
    echo "⌚ watchOS Simulator: $WATCH_DEVICE"
fi
echo ""

# Build iOS app
echo "🔨 Building iOS app..."
xcodebuild -project CareKeeper.xcodeproj \
  -scheme CareKeeperV2 \
  -destination "platform=iOS Simulator,id=$IOS_DEVICE" \
  build \
  | grep -E "(error|warning|BUILD)" \
  || echo "  (build output suppressed)"

echo ""

# Build watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "🔨 Building watchOS app..."
    xcodebuild -project CareKeeper.xcodeproj \
      -scheme "CareKeeperV2 Watch App" \
      -destination "platform=watchOS Simulator,id=$WATCH_DEVICE" \
      build \
      | grep -E "(error|warning|BUILD)" \
      || echo "  (build output suppressed)"
    echo ""
fi

# Install iOS app
echo "📲 Installing iOS app..."
xcrun simctl install "$IOS_DEVICE" \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-iphonesimulator/CareKeeperV2.app

# Install watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "📲 Installing watchOS app..."
    xcrun simctl install "$WATCH_DEVICE" \
      ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-watchsimulator/CareKeeperV2\ Watch\ App.app
fi

echo ""
echo "✅ Installation complete!"
echo ""

# Launch iOS app
echo "🚀 Launching iOS app..."
xcrun simctl launch booted com.kareemf.CareKeeperV2

# Launch watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "🚀 Launching watchOS app..."
    xcrun simctl launch booted com.kareemf.CareKeeperV2.watchkitapp
fi

echo ""
echo "✅ Apps launched successfully!"
echo ""
echo "💡 Tip: Run './scripts/sync-ios-to-watch-sim.sh' to sync data from iOS to watchOS"
