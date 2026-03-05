# Enabling Foundation Models (Sparkle Icon Feature)

**Last Updated:** January 2026

The sparkle icon (✨) feature in `ObservationsView.swift` is hidden behind a feature flag. This feature provides AI-powered summarization of observations using Apple's FoundationModels framework.

## Current Status

The feature flag `ENABLE_FOUNDATION_MODELS` is **not currently enabled** in the project build settings.

## How to Enable

### Step 1: Enable the Build Flag

1. Open your project in Xcode
2. Select your project in the Project Navigator
3. Select the **"Maria's Notebook"** target
4. Go to the **Build Settings** tab
5. Search for **"Active Compilation Conditions"** (or "Swift Compiler - Custom Flags")
6. Find the **"Swift Compiler - Custom Flags"** section
7. Under **"Active Compilation Conditions"**, add `ENABLE_FOUNDATION_MODELS`:
   - For **Debug**: Add `ENABLE_FOUNDATION_MODELS` (alongside `DEBUG`)
   - For **Release**: Add `ENABLE_FOUNDATION_MODELS`

### Step 2: Verify Framework Availability

The code also checks `canImport(FoundationModels)`. Ensure:
- You are using **Xcode 16+** (or later versions that support Apple Intelligence features)
- The `FoundationModels` framework is available to your target
- Your deployment target is set to **macOS 26.0** or later (as indicated by `@available(macOS 26.0, *)` in the code)

### Step 3: Using the Feature

Once enabled, the sparkle menu will appear in the toolbar when:
1. You tap **"Select"** in the top right of the Observations view
2. You select **at least one** observation row (a checkmark will appear)
3. The sparkle icon (✨) will appear in the toolbar with options:
   - **Key Points**: Generate a bullet-point summary
   - **Narrative**: Generate a paragraph summary

## Files Affected

The following files use the `ENABLE_FOUNDATION_MODELS` flag:
- `Components/ObservationsView.swift` - Main sparkle menu implementation
- `Components/UnifiedNoteEditor.swift` - Additional FoundationModels features
- Additional files throughout the codebase (40+ files use this flag)

## Troubleshooting

### Sparkle icon not appearing?

1. **Check the build flag**: Verify `ENABLE_FOUNDATION_MODELS` is set in both Debug and Release configurations
2. **Check Xcode version**: Ensure you're using Xcode 16+ with Apple Intelligence support
3. **Check selection state**: The sparkle menu only appears when:
   - Selection mode is active (tapped "Select")
   - At least one item is selected
4. **Clean build**: Try a clean build (Product → Clean Build Folder) after adding the flag

### Compilation errors?

- Ensure your deployment target supports macOS 26.0+
- Verify the FoundationModels framework is available in your Xcode version
- Check that all `#if ENABLE_FOUNDATION_MODELS` blocks are properly closed

## Current Build Settings

As of the last check, the project file shows:
- Debug: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"`
- Release: (No explicit `SWIFT_ACTIVE_COMPILATION_CONDITIONS` set)

To enable, these should be updated to:
- Debug: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG ENABLE_FOUNDATION_MODELS $(inherited)"`
- Release: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "ENABLE_FOUNDATION_MODELS $(inherited)"`


