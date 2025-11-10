#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="CareKeeper/Shared/Config.plist"
FORCE_REGEN=${FORCE_CONFIG_REGEN:-0}
IS_CI=${CI:-}

# On developer machines keep any manually managed file, but in CI (or when forced)
# regenerate so we always embed the latest env-provided values.
if [[ -f "$CONFIG_PATH" && -z "$IS_CI" && "$FORCE_REGEN" != "1" ]]; then
  echo "Config.plist already exists; skipping generation."
  exit 0
fi

if [[ -f "$CONFIG_PATH" ]]; then
  echo "Overwriting existing Config.plist (CI or FORCE_CONFIG_REGEN=1)."
fi

: "${CLOUDKIT_CONTAINER_ID?Environment variable CLOUDKIT_CONTAINER_ID is required}"
: "${APP_GROUP_IDENTIFIER?Environment variable APP_GROUP_IDENTIFIER is required}"
ZONE_NAME_VALUE=${ZONE_NAME:-com.example.carekeeper.zone}

cat > "$CONFIG_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CLOUDKIT_CONTAINER_ID</key>
    <string>$CLOUDKIT_CONTAINER_ID</string>
    <key>APP_GROUP_IDENTIFIER</key>
    <string>$APP_GROUP_IDENTIFIER</string>
    <key>ZONE_NAME</key>
    <string>$ZONE_NAME_VALUE</string>
</dict>
</plist>
PLIST

echo "Generated $CONFIG_PATH"
