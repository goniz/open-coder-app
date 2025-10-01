# Rules Swift Package Manager Reproducible Patch

## Overview

This patch makes the `swift_deps` module extension from `rules_swift_package_manager` reproducible by adding `reproducible = True` to the extension metadata. This prevents absolute paths from being written to the `MODULE.bazel.lock` file, making the lockfile portable across different machines and user directories.

## Current Patch

Location: `patches/rules-swift-package-manager-reproducible.patch`

The patch modifies `swiftpkg/bzlmod/swift_deps.bzl` to add `reproducible = True` to the `extension_metadata` return value in the `_swift_deps_impl` function.

## How It Works

According to [Bazel documentation](https://bazel.build/external/extension#specify_reproducibility), an extension should be marked as reproducible if it:
- Always defines the same repositories given the same inputs
- Doesn't rely on downloads without checksums
- Doesn't depend on the host environment (or uses `os_dependent`/`arch_dependent` flags appropriately)

By marking the extension as reproducible, Bazel can skip re-evaluating it and avoid including environment-specific data (like absolute paths) in the lockfile.

## Updating the Patch for New Versions

If you need to update `rules_swift_package_manager` to a newer version, follow these steps:

### 1. Check if the patch is still needed

```bash
# Download the new version's extensions file
curl -L "https://raw.githubusercontent.com/cgrindel/rules_swift_package_manager/v<NEW_VERSION>/swiftpkg/bzlmod/swift_deps.bzl" > /tmp/swift_deps.bzl

# Check if reproducible is already set
grep "reproducible = True" /tmp/swift_deps.bzl
```

If the output shows `reproducible = True` is already present, the patch is no longer needed and you can remove it.

### 2. Update MODULE.bazel

Update the version and download URL in `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_swift_package_manager", version = "<NEW_VERSION>")

archive_override(
    module_name = "rules_swift_package_manager",
    integrity = "sha256-PLACEHOLDER",  # Will be corrected by Bazel
    patch_strip = 1,
    patches = ["//:patches/rules-swift-package-manager-reproducible.patch"],
    urls = ["https://github.com/cgrindel/rules_swift_package_manager/releases/download/v<NEW_VERSION>/rules_swift_package_manager.v<NEW_VERSION>.tar.gz"],
)
```

### 3. Let Bazel calculate the correct integrity hash

```bash
bazel mod tidy
```

Bazel will report the actual hash. Copy it and update `MODULE.bazel` with the correct `integrity` value.

### 4. Regenerate the patch if needed

If the file structure changed and the patch fails to apply:

```bash
# Download and extract the new version
cd /tmp
curl -L "https://github.com/cgrindel/rules_swift_package_manager/releases/download/v<NEW_VERSION>/rules_swift_package_manager.v<NEW_VERSION>.tar.gz" | tar xz
cd rules_swift_package_manager

# Make your changes to swiftpkg/bzlmod/swift_deps.bzl
# Find the _swift_deps_impl function and locate the return statement:
#   return module_ctx.extension_metadata(
#       root_module_direct_deps = direct_dep_repo_names,
#       root_module_direct_dev_deps = [],
#   )
# 
# Add reproducible = True:
#   return module_ctx.extension_metadata(
#       root_module_direct_deps = direct_dep_repo_names,
#       root_module_direct_dev_deps = [],
#       reproducible = True,
#   )

# Generate the patch
git init
git add .
git commit -m "original"
# Make your changes
git add swiftpkg/bzlmod/swift_deps.bzl
git commit -m "add reproducible"
git format-patch HEAD~1 --stdout > ~/PersonalProjects/open-coder-app/patches/rules-swift-package-manager-reproducible.patch
```

### 5. Test the patch

```bash
cd ~/PersonalProjects/open-coder-app
bazel mod tidy
bazel clean --expunge
bazel build //...
```

### 6. Verify reproducibility

Check that absolute paths are not in the lockfile:

```bash
grep "/Users/$(whoami)" MODULE.bazel.lock
# Should return no matches
```

## Troubleshooting

### Patch fails to apply

If the patch fails with "Hunk failed", the file structure has changed. Follow step 4 to regenerate the patch.

### Extension metadata signature changed

If `extension_metadata` accepts different parameters in the new version, check the Bazel documentation and update accordingly:
- [Bazel Module Extensions](https://bazel.build/external/extension)
- [extension_metadata API](https://bazel.build/rules/lib/builtins/module_ctx#extension_metadata)

### Reproducible flag not working

Ensure you're adding `reproducible = True` to the return value of `extension_metadata()`, not as a parameter to `module_extension()`.

## Removing the Patch

If a future version of `rules_swift_package_manager` includes `reproducible = True` by default:

1. Remove the patch file: `rm patches/rules-swift-package-manager-reproducible.patch`
2. Remove the `archive_override` from `MODULE.bazel`
3. Keep only the `bazel_dep` line with the new version
4. Run `bazel mod tidy` to update the lockfile
