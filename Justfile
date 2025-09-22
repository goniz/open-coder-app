build:
    swift build -Xswiftc -warnings-as-errors --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios17.0-simulator

test:
    swift test --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios17.0-simulator

update:
    swift package update

lint:
    swiftlint Sources --strict

fix:
    swiftlint Sources --fix

fmt:
    swift-format --in-place --recursive Sources/

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
    mv opencode_api_generated.yaml Sources/OpenAPIGenerated/openapi.yaml

watch:
    python3 scripts/watch_sources.py
