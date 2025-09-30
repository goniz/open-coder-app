fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build for development without publishing

### ios preview

```sh
[bundle exec] fastlane ios preview
```

Build preview IPA using Bazel

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate screenshots for development

### ios appstore

```sh
[bundle exec] fastlane ios appstore
```

Publish to App Store using Bazel-built IPA

### ios check_builds

```sh
[bundle exec] fastlane ios check_builds
```

Check TestFlight build processing status

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
