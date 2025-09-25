build:
    @echo "Building OpenCoderCore (macOS + iOS)..."
    cd Packages/OpenCoderCore && swift build -Xswiftc -warnings-as-errors
    @echo "Building OpenCoderUI (iOS)..."
    cd Packages/OpenCoderUI && swift build -Xswiftc -warnings-as-errors --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios17.0-simulator
    @echo "Building OpenCoderApp (iOS)..."
    cd Packages/OpenCoderApp && swift build -Xswiftc -warnings-as-errors --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios17.0-simulator

test:
    @echo "Testing OpenCoderCore..."
    cd Packages/OpenCoderCore && swift test

build-core-macos:
    cd Packages/OpenCoderCore && swift build -Xswiftc -warnings-as-errors

update:
    swift package update

lint:
    swiftlint Packages/OpenCoderCore/Sources --strict
    swiftlint Packages/OpenCoderUI/Sources --strict  
    swiftlint Packages/OpenCoderApp/Sources --strict

fix:
    swiftlint Packages/OpenCoderCore/Sources --fix
    swiftlint Packages/OpenCoderUI/Sources --fix
    swiftlint Packages/OpenCoderApp/Sources --fix

fmt:
    swift-format --in-place --recursive Packages/OpenCoderCore/Sources/
    swift-format --in-place --recursive Packages/OpenCoderUI/Sources/
    swift-format --in-place --recursive Packages/OpenCoderApp/Sources/

build-ios:
    cd Xcode && fastlane build

beta:
    cd Xcode && fastlane beta

preview:
    cd Xcode && fastlane preview

check_builds:
    cd Xcode && fastlane check_builds

devcycle:
    just lint && \
    just build && \
    just build-ios && \
    just test

ota-host *args:
    cd swift-ota-host && swift run swift-ota-host {{args}}

preview-ota *args:
    just preview && just ota-host --ipa ../Xcode/OpenCoder-Preview.ipa {{args}}

generate-opencode-api:
    OPENCODE_VERSION=`opencode --version` && \
    export OPENCODE_VERSION && \
    opencode generate | yq -P ".info.version = env(OPENCODE_VERSION) | .paths |= with_entries(.value |= with_entries(.value.parameters |= unique_by(.name + .in)))" > opencode_api_generated.yaml && \
    mv opencode_api_generated.yaml Packages/OpenCoderCore/Sources/OpenAPIGenerated/openapi.yaml

watch:
    python3 scripts/watch_sources.py
