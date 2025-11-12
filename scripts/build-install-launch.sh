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

# If no iOS device is booted, boot one
if [ -z "$IOS_DEVICE" ]; then
    echo "⚠️  No booted iPhone simulator found"
    echo "🔄 Finding available iPhone simulator to boot..."

    # Try to find iPhone 16 first, then any iPhone
    IOS_DEVICE=$(xcrun simctl list devices | grep "iPhone 16 " | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

    if [ -z "$IOS_DEVICE" ]; then
        # Fallback to any available iPhone
        IOS_DEVICE=$(xcrun simctl list devices | grep "iPhone" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi

    if [ -z "$IOS_DEVICE" ]; then
        echo "❌ No iPhone simulators found"
        echo "Please install an iPhone simulator using Xcode"
        exit 1
    fi

    echo "🚀 Booting iPhone simulator: $IOS_DEVICE"
    xcrun simctl boot "$IOS_DEVICE" 2>/dev/null || true

    # Wait for device to boot
    echo "⏳ Waiting for simulator to boot..."
    sleep 3

    # Open Simulator app
    open -a Simulator
fi

if [ -z "$WATCH_DEVICE" ]; then
    echo "⚠️  No booted Apple Watch simulator found"
    echo "🔄 Finding available Apple Watch simulator to boot..."

    # Find a watch simulator running watchOS 10.0 or higher
    # First try watchOS 26 (latest), then 11, then 10
    WATCH_DEVICE=$(xcrun simctl list devices watchOS | \
        sed -n '/-- watchOS 26/,/-- /p' | \
        grep -E "Apple Watch (Ultra|Series)" | \
        head -1 | \
        sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

    if [ -z "$WATCH_DEVICE" ]; then
        WATCH_DEVICE=$(xcrun simctl list devices watchOS | \
            sed -n '/-- watchOS 11/,/-- /p' | \
            grep "Apple Watch" | \
            head -1 | \
            sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi

    if [ -z "$WATCH_DEVICE" ]; then
        WATCH_DEVICE=$(xcrun simctl list devices watchOS | \
            sed -n '/-- watchOS 10/,/-- /p' | \
            grep "Apple Watch" | \
            head -1 | \
            sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi

    if [ -z "$WATCH_DEVICE" ]; then
        echo "⚠️  No Apple Watch simulators with watchOS 10.0+ found"
        echo "Continuing with iOS app only"
        WATCH_DEVICE=""
    else
        echo "🚀 Booting Apple Watch simulator: $WATCH_DEVICE"
        xcrun simctl boot "$WATCH_DEVICE" 2>/dev/null || true

        # Wait for device to boot
        echo "⏳ Waiting for watch simulator to boot..."
        sleep 3
    fi
fi

echo "📱 iOS Simulator: $IOS_DEVICE"
if [ -n "$WATCH_DEVICE" ]; then
    echo "⌚ watchOS Simulator: $WATCH_DEVICE"
fi
echo ""

# Build iOS app (also builds widget extension)
echo "🔨 Building iOS app..."
xcodebuild -project CareKeeper.xcodeproj \
  -scheme CareKeeper \
  -destination "platform=iOS Simulator,id=$IOS_DEVICE" \
  build \
  | grep -E "(error|warning|BUILD)" \
  || echo "  (build output suppressed)"

echo ""

# Build watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "🔨 Building watchOS app..."
    xcodebuild -project CareKeeper.xcodeproj \
      -scheme "CareKeeper Watch App" \
      -destination "platform=watchOS Simulator,id=$WATCH_DEVICE" \
      build \
      | grep -E "(error|warning|BUILD)" \
      || echo "  (build output suppressed)"
    echo ""
fi

# Install iOS app
# Install watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "📲 Installing watchOS app..."
    xcrun simctl install "$WATCH_DEVICE" \
      ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-watchsimulator/CareKeeper\ Watch\ App.app
fi

echo ""
echo "✅ Installation complete!"
echo ""

# Launch iOS app
echo "🚀 Launching iOS app..."
xcrun simctl launch "$IOS_DEVICE" com.kareemf.CareKeeper

# Launch watchOS app (if watch simulator is booted)
if [ -n "$WATCH_DEVICE" ]; then
    echo "🚀 Launching watchOS app..."
    xcrun simctl launch "$WATCH_DEVICE" com.kareemf.CareKeeper.watchkitapp
fi

echo ""
echo "✅ Apps launched successfully!"
echo ""
echo "💡 Tip: Run './scripts/sync-ios-to-watch-sim.sh' to sync data from iOS to watchOS"
# Install widget extension (iOS)
LATEST_DERIVED=$(ls -dt ~/Library/Developer/Xcode/DerivedData/CareKeeper-* 2>/dev/null | head -1)
IOS_APP_PATH="$LATEST_DERIVED/Build/Products/Debug-iphonesimulator/CareKeeper iOS.app"
WIDGET_PATH="$LATEST_DERIVED/Build/Products/Debug-iphonesimulator/CareKeeper iOS Widget.appex"

echo "📲 Installing iOS app..."
if [ -d "$IOS_APP_PATH" ]; then
  xcrun simctl install "$IOS_DEVICE" "$IOS_APP_PATH"
else
  echo "❌ iOS app bundle not found at $IOS_APP_PATH"
  exit 1
fi

if [ -d "$WIDGET_PATH" ]; then
  echo "📲 Installing iOS widget..."
  xcrun simctl install "$IOS_DEVICE" "$WIDGET_PATH"
else
  echo "⚠️ Widget build output not found; skipping widget install."
fi
