#!/bin/bash

# sync-ios-to-watch-sim.sh
#
# Syncs SwiftData database from iOS simulator to watchOS simulator for testing.
#
# Purpose: Enables end-to-end testing on simulators since the watchOS app is
# read-only for carees and activity types (these must be created on iOS).
#
# Note: This is a workaround for simulator limitations. On physical devices,
# app groups work correctly and data syncs automatically. Once CloudKit is
# enabled in Phase 2, simulators will also sync via iCloud.
#
# Usage: ./scripts/sync-ios-to-watch-sim.sh

set -e

echo "🔄 Syncing iOS Simulator data to watchOS Simulator..."

# Find the booted iOS simulator
IOS_DEVICE=$(xcrun simctl list devices | grep "iPhone.*Booted" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
if [ -z "$IOS_DEVICE" ]; then
    echo "❌ Error: No booted iPhone simulator found"
    echo "Please boot an iPhone simulator and run the iOS app first"
    exit 1
fi

# Find the booted watchOS simulator
WATCH_DEVICE=$(xcrun simctl list devices | grep "Apple Watch.*Booted" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
if [ -z "$WATCH_DEVICE" ]; then
    echo "❌ Error: No booted Apple Watch simulator found"
    echo "Please boot an Apple Watch simulator"
    exit 1
fi

echo "📱 iOS Simulator: $IOS_DEVICE"
echo "⌚ watchOS Simulator: $WATCH_DEVICE"

# Find the app group containers
SIMULATOR_ROOT="$HOME/Library/Developer/CoreSimulator/Devices"
APP_GROUP_ID="group.com.kareemf.CareKeeper"

echo "🔍 Finding app group containers..."

# Find iOS app group
IOS_METADATA_FILE=$(grep -rl "$APP_GROUP_ID" "$SIMULATOR_ROOT/$IOS_DEVICE/data/Containers/Shared/AppGroup/"*/.com.apple.mobile_container_manager.metadata.plist 2>/dev/null | head -1)
if [ -z "$IOS_METADATA_FILE" ]; then
    echo "❌ Error: iOS app group not found"
    echo "Please run the iOS app at least once to create the app group"
    exit 1
fi
IOS_APP_GROUP=$(dirname "$IOS_METADATA_FILE")

# Find watchOS app group
WATCH_METADATA_FILE=$(grep -rl "$APP_GROUP_ID" "$SIMULATOR_ROOT/$WATCH_DEVICE/data/Containers/Shared/AppGroup/"*/.com.apple.mobile_container_manager.metadata.plist 2>/dev/null | head -1)
if [ -z "$WATCH_METADATA_FILE" ]; then
    echo "❌ Error: watchOS app group not found"
    echo "Please run the watchOS app at least once to create the app group"
    exit 1
fi
WATCH_APP_GROUP=$(dirname "$WATCH_METADATA_FILE")

IOS_DB_DIR="$IOS_APP_GROUP/Library/Application Support"
WATCH_DB_DIR="$WATCH_APP_GROUP/Library/Application Support"

# Check if iOS database exists
if [ ! -f "$IOS_DB_DIR/default.store" ]; then
    echo "❌ Error: No database found in iOS app group"
    echo "Path checked: $IOS_DB_DIR"
    echo "Please run the iOS app and create some data first"
    exit 1
fi

echo "📂 iOS Database: $IOS_DB_DIR"
echo "📂 watchOS Database: $WATCH_DB_DIR"

# Create watchOS directory if it doesn't exist
mkdir -p "$WATCH_DB_DIR"

# Terminate both apps if running
echo "🛑 Stopping apps..."
xcrun simctl terminate "$IOS_DEVICE" com.kareemf.CareKeeperV2 2>/dev/null || true
xcrun simctl terminate "$WATCH_DEVICE" com.kareemf.CareKeeperV2.watchkitapp 2>/dev/null || true

# Copy database files
echo "📋 Copying database files..."
cp -v "$IOS_DB_DIR/default.store" "$WATCH_DB_DIR/" 2>&1 | sed 's/^/  /'
cp -v "$IOS_DB_DIR/default.store-wal" "$WATCH_DB_DIR/" 2>&1 | sed 's/^/  /' || true
cp -v "$IOS_DB_DIR/default.store-shm" "$WATCH_DB_DIR/" 2>&1 | sed 's/^/  /' || true

# Show database size
DB_SIZE=$(du -h "$WATCH_DB_DIR/default.store" | cut -f1)
echo "✅ Database synced successfully! ($DB_SIZE)"

echo ""
echo "🚀 You can now launch both apps:"
echo "   iOS:     xcrun simctl launch booted com.kareemf.CareKeeperV2"
echo "   watchOS: xcrun simctl launch booted com.kareemf.CareKeeperV2.watchkitapp"
echo ""
echo "📝 Note: Changes made on either simulator won't automatically sync."
echo "   Run this script again after making changes on iOS to update watchOS."
