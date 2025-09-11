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

adhoc:
    cd Xcode && fastlane adhoc

update_caps:
    cd Xcode && fastlane update_capabilities

check_builds:
    cd Xcode && fastlane check_builds

validate-ipa:
    cd Xcode && xcrun altool --validate-app -f OpenCoder.ipa -t ios --apiKey ZZR4FFP696 --apiIssuer d5f4a2be-8aae-409d-9526-b299f949a6d9

devcycle:
    just lint && \
    just build && \
    just build-ios && \
    just test

ota-host *args:
    cd swift-ota-host && swift run swift-ota-host {{args}}