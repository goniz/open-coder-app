#!/bin/sh

# Xcode Cloud post-clone script to configure macro package trust
# This script runs after the repository is cloned but before the build starts

set -e

echo "🔧 Configuring Xcode Cloud for macro packages..."

# Allow macro packages to be built and executed
# This is required for packages like DependenciesMacros from swift-dependencies
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

echo "✅ Macro package configuration completed"