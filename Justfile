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
    @echo "Building iOS app with Bazel (dev variant, no provisioning profile)..."
    bazel build //:OpenCoder.dev

beta:
    cd Xcode && fastlane appstore

preview:
    cd Xcode && fastlane preview

check_builds:
    cd Xcode && fastlane check_builds

devcycle:
    just fix && \
    just lint && \
    just preview

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
