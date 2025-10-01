#!/bin/bash
set -euo pipefail

XCODE_PROJECT="$1"
OUTPUT_FILE="$2"
TARGET_NAME="${3:-OpenCoder}"

# Extract MARKETING_VERSION and CURRENT_PROJECT_VERSION
MARKETING_VERSION=$(grep -m 1 "MARKETING_VERSION = " "$XCODE_PROJECT" | sed 's/.*MARKETING_VERSION = \(.*\);/\1/' | tr -d ' ;')
CURRENT_PROJECT_VERSION=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$XCODE_PROJECT" | sed 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/' | tr -d ' ;')

# Write to output file
cat > "$OUTPUT_FILE" << EOF
MARKETING_VERSION="$MARKETING_VERSION"
CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION"
EOF

# Extract all INFOPLIST_KEY_* settings (excluding SDK-specific ones and CFBundleDisplayName duplicates)
# Format: INFOPLIST_KEY_Name = Value;
grep "INFOPLIST_KEY_" "$XCODE_PROJECT" | \
  grep -v "sdk=" | \
  grep -v "INFOPLIST_KEY_CFBundleDisplayName" | \
  sed 's/.*INFOPLIST_KEY_//' | \
  sed 's/ = /=/' | \
  sed 's/;$//' | \
  sed 's/"//g' | \
  awk -F= '!seen[$1]++' | \
  sort | \
  while IFS='=' read -r key value; do
    if [ -n "$key" ]; then
      # Quote values to handle spaces
      echo "INFOPLIST_KEY_${key}=\"${value}\"" >> "$OUTPUT_FILE"
    fi
  done

echo "Extracted all settings for target '$TARGET_NAME'" >&2