build:
    swift build

test:
    swift test

update:
    swift package update

lint:
    swiftlint Sources

beta:
    cd Xcode && fastlane beta