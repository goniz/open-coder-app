#!/bin/bash
set -euo pipefail

SETTINGS_FILE="$1"
OUTPUT_PLIST="$2"
DISPLAY_NAME="$3"

# Source the settings file
source "$SETTINGS_FILE"

# Function to convert space-separated string to plist array
# Usage: array_value "item1 item2 item3"
array_value() {
  local items="$1"
  echo "	<array>"
  for item in $items; do
    echo "		<string>$item</string>"
  done
  echo "	</array>"
}

# Create Info.plist
cat > "$OUTPUT_PLIST" << 'PLIST_START'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
PLIST_START

# Add display name (from parameter)
cat >> "$OUTPUT_PLIST" << EOF
	<key>CFBundleDisplayName</key>
	<string>$DISPLAY_NAME</string>
EOF

# Add CFBundleIconName if present
if [ -n "${INFOPLIST_KEY_CFBundleIconName:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>CFBundleIconName</key>
	<string>$INFOPLIST_KEY_CFBundleIconName</string>
EOF
fi

# Static keys
cat >> "$OUTPUT_PLIST" << EOF
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>OpenCoder</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$MARKETING_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$CURRENT_PROJECT_VERSION</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
EOF

# Add LSApplicationCategoryType if present
if [ -n "${INFOPLIST_KEY_LSApplicationCategoryType:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>LSApplicationCategoryType</key>
	<string>$INFOPLIST_KEY_LSApplicationCategoryType</string>
EOF
fi

# Add ITSAppUsesNonExemptEncryption if present
if [ -n "${INFOPLIST_KEY_ITSAppUsesNonExemptEncryption:-}" ]; then
  if [ "$INFOPLIST_KEY_ITSAppUsesNonExemptEncryption" = "NO" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
EOF
  else
cat >> "$OUTPUT_PLIST" << EOF
	<key>ITSAppUsesNonExemptEncryption</key>
	<true/>
EOF
  fi
fi

# Add UIApplicationSceneManifest (for SwiftUI apps)
cat >> "$OUTPUT_PLIST" << EOF
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<true/>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIStatusBarStyle</key>
	<string>UIStatusBarStyleDefault</string>
EOF

# Add UIBackgroundModes if present
if [ -n "${INFOPLIST_KEY_UIBackgroundModes:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>UIBackgroundModes</key>
EOF
array_value "$INFOPLIST_KEY_UIBackgroundModes" >> "$OUTPUT_PLIST"
fi

# Add BGTaskSchedulerPermittedIdentifiers if present
if [ -n "${INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>BGTaskSchedulerPermittedIdentifiers</key>
EOF
array_value "$INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers" >> "$OUTPUT_PLIST"
fi

# Add NSCameraUsageDescription if present
if [ -n "${INFOPLIST_KEY_NSCameraUsageDescription:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>NSCameraUsageDescription</key>
	<string>$INFOPLIST_KEY_NSCameraUsageDescription</string>
EOF
fi

# Add NSMicrophoneUsageDescription if present
if [ -n "${INFOPLIST_KEY_NSMicrophoneUsageDescription:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>NSMicrophoneUsageDescription</key>
	<string>$INFOPLIST_KEY_NSMicrophoneUsageDescription</string>
EOF
fi

# Add NSPhotoLibraryUsageDescription if present
if [ -n "${INFOPLIST_KEY_NSPhotoLibraryUsageDescription:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>NSPhotoLibraryUsageDescription</key>
	<string>$INFOPLIST_KEY_NSPhotoLibraryUsageDescription</string>
EOF
fi

# Static capabilities array (arm64 for modern iOS)
cat >> "$OUTPUT_PLIST" << EOF
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
EOF

# Add UISupportedInterfaceOrientations if present
if [ -n "${INFOPLIST_KEY_UISupportedInterfaceOrientations:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>UISupportedInterfaceOrientations</key>
EOF
array_value "$INFOPLIST_KEY_UISupportedInterfaceOrientations" >> "$OUTPUT_PLIST"
fi

# Add UISupportedInterfaceOrientations~ipad if present
if [ -n "${INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad:-}" ]; then
cat >> "$OUTPUT_PLIST" << EOF
	<key>UISupportedInterfaceOrientations~ipad</key>
EOF
array_value "$INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad" >> "$OUTPUT_PLIST"
fi

# Close plist
cat >> "$OUTPUT_PLIST" << EOF
</dict>
</plist>
EOF

echo "Generated Info.plist at $OUTPUT_PLIST" >&2