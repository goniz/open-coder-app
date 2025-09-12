#!/bin/sh

# Xcode Cloud pre-build script
# This script runs before xcodebuild starts

set -e

echo "🔧 Xcode Cloud pre-build setup..."

# Configure macro package trust (required for TCA and other macro packages)
echo "📦 Configuring macro package trust..."
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Install dependencies if needed
echo "📥 Installing dependencies..."

# Check if we need to install any tools (though most should be available in Xcode Cloud)
if command -v brew >/dev/null 2>&1; then
    echo "🍺 Homebrew available, checking for tools..."
    
    # Install SwiftLint if available
    if ! command -v swiftlint >/dev/null 2>&1; then
        echo "📦 Installing SwiftLint..."
        brew install swiftlint || echo "⚠️ SwiftLint installation failed, continuing..."
    fi
    
    # Install just if available
    if ! command -v just >/dev/null 2>&1; then
        echo "📦 Installing just..."
        brew install just || echo "⚠️ Just installation failed, continuing..."
    fi
else
    echo "⚠️ Homebrew not available in Xcode Cloud environment"
fi

# Verify Swift Package Manager dependencies
echo "🔍 Resolving Swift Package dependencies..."
swift package resolve

echo "✅ Pre-build setup completed"