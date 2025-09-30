# Research: Generating Info.plist from Xcode Project

## Question
Can we generate the entire Info.plist file from Xcode project.pbxproj using existing tools (Fastlane, Bazel rules, or Xcode command-line tools)?

## Summary
**Yes, but with limitations.** There's no single tool that does this out-of-the-box, but it's achievable with custom scripting using existing command-line tools.

---

## Available Tools

### 1. **xcodebuild -showBuildSettings**

**Capabilities:**
- Extracts **all** build settings from Xcode project for a specific target and configuration
- Includes `INFOPLIST_KEY_*` values that map directly to Info.plist keys
- Can output in plain text or JSON format (with `-json` flag)
- Official Apple tool, part of Xcode Command Line Tools

**Example:**
```bash
xcodebuild -project OpenCoder.xcodeproj \
  -target "OpenCoder" \
  -configuration Release \
  -showBuildSettings -json
```

**Output includes:**
- `MARKETING_VERSION` → CFBundleShortVersionString
- `CURRENT_PROJECT_VERSION` → CFBundleVersion
- `PRODUCT_BUNDLE_IDENTIFIER` → CFBundleIdentifier
- `INFOPLIST_KEY_CFBundleDisplayName` → CFBundleDisplayName
- `INFOPLIST_KEY_LSApplicationCategoryType` → LSApplicationCategoryType
- `INFOPLIST_KEY_UIBackgroundModes` → UIBackgroundModes
- All other `INFOPLIST_KEY_*` settings

**Advantages:**
- ✅ Official Apple tool, guaranteed to stay up-to-date
- ✅ Handles all build configurations and targets
- ✅ JSON output for easy parsing
- ✅ Includes computed/inherited values
- ✅ No third-party dependencies

**Disadvantages:**
- ❌ Requires Xcode to be installed
- ❌ Requires Swift package resolution (can be slow/fail if packages have issues)
- ❌ Requires target-specific invocation (need to know target names)
- ❌ Output includes hundreds of unrelated build settings
- ❌ No built-in plist generation - needs custom parsing

---

### 2. **PlistBuddy**

**Capabilities:**
- Read and write plist files (both XML and binary formats)
- Manipulate plist structure programmatically
- Part of macOS (located at `/usr/libexec/PlistBuddy`)

**Example:**
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 194" Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist
```

**Advantages:**
- ✅ Built into macOS, no installation needed
- ✅ Simple command-line interface
- ✅ Can create plists from scratch

**Disadvantages:**
- ❌ Cannot read Xcode project files directly
- ❌ Only works with existing plist files
- ❌ Not designed for plist generation from build settings

**Use case for us:** 
Could be used to **create** the plist file programmatically after parsing build settings from elsewhere.

---

### 3. **agvtool (Apple Generic Versioning Tool)**

**Capabilities:**
- Get/set `CFBundleVersion` (build number)
- Get/set `CFBundleShortVersionString` (marketing version)
- Works directly with Xcode projects

**Example:**
```bash
agvtool what-version              # Get build number
agvtool what-marketing-version    # Get version string
agvtool new-version 195           # Increment build number
```

**Advantages:**
- ✅ Built into Xcode Command Line Tools
- ✅ Simple interface for version management
- ✅ Used by Fastlane's `increment_build_number`

**Disadvantages:**
- ❌ **Only handles version numbers** - nothing else
- ❌ Cannot extract other Info.plist keys
- ❌ Limited scope

**Use case for us:** 
We already use this indirectly via Fastlane's `increment_build_number`.

---

### 4. **Fastlane**

**Relevant Actions:**
- `get_build_number`: Gets `CFBundleVersion` from Xcode project
- `get_info_plist_value`: Reads values from **existing** Info.plist files
- `increment_build_number`: Increments build number in Xcode project
- No action for extracting INFOPLIST_KEY_* settings

**Example:**
```ruby
build_number = get_build_number(xcodeproj: "OpenCoder.xcodeproj")
bundle_id = get_info_plist_value(path: "Info.plist", key: "CFBundleIdentifier")
```

**Advantages:**
- ✅ High-level Ruby API
- ✅ Well-documented and maintained
- ✅ Integrates with existing workflows

**Disadvantages:**
- ❌ No built-in action to extract all INFOPLIST_KEY_* settings
- ❌ `get_info_plist_value` requires **existing** plist file
- ❌ Would need custom Ruby scripting to parse project.pbxproj

**Use case for us:** 
Fastlane is great for **reading existing plists** and **incrementing versions**, but not for generating plists from scratch.

---

### 5. **Bazel rules_apple**

**Capabilities:**
- `ios_application` rule accepts `infoplists` parameter
- Can process plist templates with variable substitution
- Has built-in rules for asset catalogs, resources, etc.

**From rules_apple documentation:**
- The `infoplists` attribute accepts a list of plist files
- Bazel merges multiple plists automatically
- No built-in rule to extract settings from Xcode projects

**Example:**
```python
ios_application(
    name = "App",
    infoplists = [":Info.plist"],  # Expects existing file
    # ...
)
```

**Advantages:**
- ✅ Well-designed build system
- ✅ Handles plist merging automatically
- ✅ Supports plist preprocessing

**Disadvantages:**
- ❌ No built-in Xcode project parser
- ❌ Expects plist files as inputs
- ❌ Would require custom Starlark rules

**Use case for us:** 
We can create custom Bazel rules (which we already did) to parse Xcode projects and generate plists.

---

## Proposed Solution Architecture

### **Hybrid Approach: xcodebuild + Custom Parsing**

Since no single tool does this out-of-the-box, the best approach is:

1. **Use `xcodebuild -showBuildSettings -json`** to extract all build settings
2. **Parse JSON output** to extract `INFOPLIST_KEY_*` and version settings
3. **Generate Info.plist** using template or direct plist creation

### Implementation Options:

#### **Option A: Enhanced Bash Script (Quick Win)**

```bash
#!/bin/bash
# Extract build settings as JSON
xcodebuild -project Xcode/OpenCoder.xcodeproj \
  -target "OpenCoder" \
  -configuration Release \
  -showBuildSettings -json > build_settings.json

# Parse JSON and generate plist using Python/Ruby/jq
# Map INFOPLIST_KEY_* → Info.plist keys
# Generate plist file

# Pseudo-code mapping:
# INFOPLIST_KEY_CFBundleDisplayName → CFBundleDisplayName
# INFOPLIST_KEY_UIBackgroundModes → UIBackgroundModes (split string to array)
# MARKETING_VERSION → CFBundleShortVersionString
# CURRENT_PROJECT_VERSION → CFBundleVersion
```

**Pros:** 
- Uses official Apple tools
- Can extract **all** plist keys
- Single source of truth (Xcode project)

**Cons:**
- Requires Xcode installation
- Slower (needs package resolution)
- Custom parsing logic needed

---

#### **Option B: Direct project.pbxproj Parsing (Current Approach)**

Our current implementation:
```bash
# Extract versions only
grep -m 1 "MARKETING_VERSION = " project.pbxproj
grep -m 1 "CURRENT_PROJECT_VERSION = " project.pbxproj
grep "INFOPLIST_KEY_" project.pbxproj
```

**Pros:**
- ✅ Fast (no Xcode needed)
- ✅ Simple text parsing
- ✅ Works in CI environments
- ✅ Already implemented

**Cons:**
- ❌ Fragile (depends on project.pbxproj format)
- ❌ Doesn't handle computed values
- ❌ Requires understanding project.pbxproj structure
- ❌ Must handle target-specific settings manually

---

#### **Option C: Bazel + xcodebuild (Best of Both)**

Enhance our current Bazel rules to use `xcodebuild`:

```python
def _extract_all_build_settings_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    
    ctx.actions.run_shell(
        inputs = [ctx.file.xcode_project],
        outputs = [output],
        command = """
        xcodebuild -project {project_dir} \
          -target {target} \
          -configuration {config} \
          -showBuildSettings -json > {output}
        """.format(
            project_dir = ctx.file.xcode_project.dirname,
            target = ctx.attr.target_name,
            config = ctx.attr.configuration,
            output = output.path,
        ),
    )
    return [DefaultInfo(files = depset([output]))]
```

**Pros:**
- ✅ Uses official Apple tools
- ✅ Handles all edge cases
- ✅ Integrated into Bazel build
- ✅ Can extract **everything**

**Cons:**
- ❌ Slower builds (xcodebuild invocation)
- ❌ Requires Xcode in CI
- ❌ More complex implementation

---

## Comparison Matrix

| Tool | Can Extract All Keys | Speed | Reliability | Complexity | CI-Friendly |
|------|---------------------|-------|-------------|------------|-------------|
| xcodebuild -showBuildSettings | ✅ Yes | 🐌 Slow | ⭐⭐⭐⭐⭐ Official | ⭐⭐⭐ Medium | ❌ Needs Xcode |
| project.pbxproj parsing (current) | ⚠️ Manual | ⚡ Fast | ⭐⭐⭐ Fragile | ⭐⭐ Simple | ✅ Yes |
| PlistBuddy | ❌ No (only writes) | ⚡ Fast | ⭐⭐⭐⭐⭐ Built-in | ⭐ Very Simple | ✅ Yes |
| agvtool | ❌ Only versions | ⚡ Fast | ⭐⭐⭐⭐⭐ Official | ⭐ Very Simple | ✅ Yes |
| Fastlane | ❌ No built-in | ⚡ Fast | ⭐⭐⭐⭐ Popular | ⭐⭐⭐ Medium | ✅ Yes |
| rules_apple | ❌ No built-in | ⚡ Fast | ⭐⭐⭐⭐ Bazel | ⭐⭐⭐⭐ Complex | ✅ Yes |

---

## Recommendation

### **For Our Use Case:**

**Keep the current approach** (project.pbxproj parsing) because:

1. ✅ **It works** - Already extracting versions and display names
2. ✅ **Fast builds** - No Xcode invocation needed
3. ✅ **CI-friendly** - Works without Xcode installation
4. ✅ **Minimal dependencies** - Just grep/sed
5. ✅ **Template-based** - Easy to maintain plist structure

### **Potential Enhancement:**

Add script to extract INFOPLIST_KEY_* values from project.pbxproj:

```bash
# Extract all INFOPLIST_KEY settings for a target
grep "INFOPLIST_KEY_" project.pbxproj | \
  sed 's/.*INFOPLIST_KEY_\([^ ]*\) = \(.*\);/\1=\2/' | \
  sort -u
```

This would allow us to:
- Generate complete plists from Xcode
- Keep fast builds
- Maintain CI compatibility
- Avoid xcodebuild slowness

### **When to Consider xcodebuild:**

If we need:
- Complex computed build settings
- SDK-specific values (`[sdk=iphoneos*]`)
- Inherited configuration values
- Multiple target configurations automatically

---

## Conclusion

**Answer:** Yes, it's possible to generate entire Info.plist from Xcode project using existing tools, but **no single tool does it automatically**.

**Best approach for this project:**
- Continue using **project.pbxproj parsing** (fast, simple, CI-friendly)
- Optionally enhance to extract more `INFOPLIST_KEY_*` settings if needed
- Keep template for structure and rarely-changing values
- Use Xcode project as source of truth for dynamic values only

**If we needed full automation:**
- Use `xcodebuild -showBuildSettings -json` with custom parsing
- Trade speed for completeness
- Better for projects with complex build configurations
---

## Update: rules_xcodeproj

**Question:** Does rules_xcodeproj support extracting settings from Xcode projects?

**Answer:** No. `rules_xcodeproj` is a **one-way tool** that generates Xcode projects FROM Bazel targets.

### What it does:
- ✅ Generates `.xcodeproj` files from Bazel BUILD definitions
- ✅ Enables development in Xcode while building with Bazel
- ✅ Maps Bazel targets to Xcode schemes and targets

### What it does NOT do:
- ❌ Parse existing Xcode projects
- ❌ Extract build settings from project.pbxproj
- ❌ Generate Info.plist from Xcode settings

### Use case:
`rules_xcodeproj` is for teams that want to:
- Build with Bazel (for reproducibility and speed)
- Develop in Xcode (for IDE features)

Our use case is the **opposite direction**: we have an existing Xcode project and want to extract its settings for Bazel builds.

### Conclusion:
`rules_xcodeproj` doesn't help with our use case. Our current approach (parsing project.pbxproj directly) remains the best solution.
