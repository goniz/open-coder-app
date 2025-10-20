test:
    @echo "Testing OpenCoderCore..."
    bazel test //Packages/OpenCoderCore:OpenCoderCoreTests

build-core-macos:
    cd Packages/OpenCoderCore && swift build -Xswiftc -warnings-as-errors

update:
    swift package --package-path Packages/OpenCoderCore/Sources update
    swift package --package-path Packages/OpenCoderUI/Sources update
    swift package --package-path Packages/OpenCoderApp/Sources update
    swift package update

lint args="":
    swiftlint Packages/OpenCoderCore/Sources Packages/OpenCoderUI/Sources Packages/OpenCoderApp/Sources --strict {{args}}

fix args="":
    swiftlint Packages/OpenCoderCore/Sources Packages/OpenCoderUI/Sources Packages/OpenCoderApp/Sources --fix {{args}}

fmt:
    swift-format --in-place --recursive Packages/OpenCoderCore/Sources/
    swift-format --in-place --recursive Packages/OpenCoderUI/Sources/
    swift-format --in-place --recursive Packages/OpenCoderApp/Sources/

build-ios:
    @echo "Building iOS app with Bazel (dev variant, no provisioning profile)..."
    bazel build //:OpenCoder.dev

beta:
    cd Xcode && fastlane appstore

preview quiet="false":
    #!/usr/bin/env bash
    set -euo pipefail
    
    BAZEL_FLAGS="--config=release"
    if [ "{{quiet}}" = "true" ]; then
        BAZEL_FLAGS="$BAZEL_FLAGS --ui_event_filters=-info,-debug --noshow_progress"
        cd Xcode && fastlane fetch_credentials > /dev/null 2>&1
    else
        echo "Fetching credentials..."
        cd Xcode && fastlane fetch_credentials
        echo "Building preview IPA with Bazel..."
    fi
    
    bazel build $BAZEL_FLAGS //:OpenCoder.preview
    
    if [ "{{quiet}}" = "false" ]; then
        echo "✅ Preview IPA built: bazel-bin/OpenCoder.preview.ipa"
    fi

run-simulator:
   bazel run --config=simulator //:OpenCoder.dev

build-simulator:
    bazel build --config=simulator //:OpenCoder.dev

devcycle:
    just fix --quiet && \
    just lint --quiet && \
    just preview quiet=true

ota-host *args:
    cd swift-ota-host && swift run swift-ota-host {{args}}

ota-host-unblock:
    @echo "Unblocking swift-ota-host binary in firewall..."
    cd swift-ota-host && \
    swift build && \
    codesign --sign - --force --deep .build/debug/swift-ota-host && \
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $(pwd)/.build/debug/swift-ota-host && \
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblock $(pwd)/.build/debug/swift-ota-host && \
    echo "✅ Binary unblocked and added to firewall"

preview-ota *args:
    just preview && just ota-host --ipa ../bazel-bin/OpenCoder.preview.ipa {{args}}

generate-opencode-api:
    OPENCODE_VERSION=`opencode --version` && \
    export OPENCODE_VERSION && \
    opencode generate | yq -P ".info.version = env(OPENCODE_VERSION) | .paths |= with_entries(.value |= with_entries(.value.parameters |= unique_by(.name + .in)))" > opencode_api_generated.yaml && \
    mv opencode_api_generated.yaml Packages/OpenCoderCore/Sources/OpenAPIGenerated/openapi.yaml && \
    echo "Generating Swift code from OpenAPI..." && \
    cd Packages/OpenCoderCore && \
    swift run swift-openapi-generator generate \
        --mode types --mode client \
        --config Sources/OpenAPIGenerated/openapi-generator-config.yaml \
        --output-directory Sources/OpenAPIGenerated \
        Sources/OpenAPIGenerated/openapi.yaml

watch:
    python3 scripts/watch_sources.py

test-integration:
    @echo "Running integration tests..."
    bazel test //Packages/OpenCoderCore:ImplementationsIntegrationTests --test_output=errors --test_timeout=300
