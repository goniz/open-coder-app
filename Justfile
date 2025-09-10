build:
    swift build -Xswiftc -warnings-as-errors

test:
    swift test

update:
    swift package update

lint:
    swiftlint Sources

fmt:
    swift-format --in-place --recursive Sources/

build-ios:
    cd Xcode && fastlane build

beta:
    cd Xcode && fastlane beta

update_caps:
    cd Xcode && fastlane update_capabilities

check_builds:
    cd Xcode && fastlane check_builds

validate-ipa:
    cd Xcode && xcrun altool --validate-app -f OpenCoder.ipa -t ios --apiKey ZZR4FFP696 --apiIssuer d5f4a2be-8aae-409d-9526-b299f949a6d9

validate:
    just build
    just build-ios
    just lint
    just test