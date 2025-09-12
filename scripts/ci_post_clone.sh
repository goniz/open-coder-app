#!/bin/sh

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before any build steps

set -e

echo "🔧 Xcode Cloud post-clone setup..."

# Configure macro package trust (required for TCA and other macro packages)
echo "📦 Configuring macro package trust..."
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Set up environment for custom workflows
echo "🌍 Setting up environment..."
export CI=true
export XCODE_CLOUD=true

# Install additional tools if available
if command -v brew >/dev/null 2>&1; then
    echo "🍺 Installing additional tools..."
    
    # Install just command runner
    if ! command -v just >/dev/null 2>&1; then
        echo "📦 Installing just..."
        brew install just || echo "⚠️ Just installation failed, will use direct commands"
    fi
    
    # Install SwiftLint for code quality
    if ! command -v swiftlint >/dev/null 2>&1; then
        echo "📦 Installing SwiftLint..."
        brew install swiftlint || echo "⚠️ SwiftLint installation failed, skipping linting"
    fi
else
    echo "⚠️ Homebrew not available, using built-in tools only"
fi

# Verify project structure
echo "🔍 Verifying project structure..."
if [ -f "Package.swift" ]; then
    echo "✅ Swift Package found"
else
    echo "❌ Swift Package not found"
    exit 1
fi

if [ -d "Xcode/OpenCoder.xcworkspace" ]; then
    echo "✅ iOS workspace found"
else
    echo "❌ iOS workspace not found"
    exit 1
fi

echo "✅ Post-clone setup completed"