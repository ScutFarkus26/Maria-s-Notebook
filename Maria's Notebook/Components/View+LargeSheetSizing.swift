import SwiftUI

/// Standardized sheet size presets for consistent sizing across the app
enum SheetSizePreset {
    /// Large sheets for detail views (StudentDetail, WorkDetail) - 720×640
    case large
    /// Medium sheets for editors and complex forms - 520×560
    case medium
    /// Small sheets for simple dialogs - 420×480
    case small
    /// Compact sheets for minimal dialogs - 400×400
    case compact
    /// Note editor sheets - 480×560
    case note

    var size: CGSize {
        switch self {
        case .large: return UIConstants.SheetSize.large
        case .medium: return UIConstants.SheetSize.medium
        case .small: return UIConstants.SheetSize.small
        case .compact: return UIConstants.SheetSize.compact
        case .note: return UIConstants.SheetSize.note
        }
    }
}

/// ViewModifier that conditionally applies presentationSizing for macOS 15.0+
private struct PresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// ViewModifier that applies standardized sheet sizing based on preset
private struct SheetSizingModifier: ViewModifier {
    let preset: SheetSizePreset
    let allowMediumDetent: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(minWidth: preset.size.width, minHeight: preset.size.height)
            .presentationSizingFitted()
        #else
        content
            .presentationDetents(allowMediumDetent ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}

extension View {
    /// Applies presentation sizing that fits content, with availability check for macOS 15.0+
    func presentationSizingFitted() -> some View {
        self.modifier(PresentationSizingModifier())
    }

    /// Applies standardized sheet sizing based on the specified preset
    /// - Parameters:
    ///   - preset: The size preset to apply
    ///   - allowMediumDetent: On iOS, allows the sheet to start at medium height (default: false)
    /// - Returns: A view with appropriate sheet sizing for the current platform
    func sheetSizing(_ preset: SheetSizePreset, allowMediumDetent: Bool = false) -> some View {
        self.modifier(SheetSizingModifier(preset: preset, allowMediumDetent: allowMediumDetent))
    }

    /// Applies flexible sheet sizing that allows medium detent on iOS (iPhone-friendly for quick edits)
    /// On macOS, uses the standard preset sizing
    func flexibleSheetSizing(_ preset: SheetSizePreset = .medium) -> some View {
        self.modifier(SheetSizingModifier(preset: preset, allowMediumDetent: true))
    }

    /// Legacy method - applies large sheet sizing (720×640 on macOS)
    @ViewBuilder
    func largeSheetSizing() -> some View {
        self.sheetSizing(.large)
    }

    /// Adds interactive keyboard dismissal on scroll for iOS
    /// On macOS, this is a no-op as keyboard behavior is different
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}
