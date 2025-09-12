build:
    swift build -Xswiftc -warnings-as-errors

test:
    swift test

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

preview-ota:
    just preview && just ota-host --ipa ../Xcode/OpenCoder-Preview.ipa

