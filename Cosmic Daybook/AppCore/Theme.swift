import SwiftUI

enum AppTheme {
    // MARK: - Fixed Font Sizes
    // Point sizes for the few places that need a fixed value. Prefer ScaledFont.
    enum FontSize {
        static let body: CGFloat = 14
        static let callout: CGFloat = 16
        static let caption: CGFloat = 13
    }

    // MARK: - Dynamic Type Scaled Fonts
    // These fonts automatically scale with the user's preferred text size
    // CDNote: All properties marked nonisolated to allow access from Sendable closures (e.g., PhotosPicker)
    enum ScaledFont {
        /// Extra large title (32pt base) - scales with .largeTitle
        /// Uses .heavy weight for strong visual anchoring at display sizes (#10)
        nonisolated static var titleXLarge: Font {
            .system(.largeTitle, design: .rounded, weight: .heavy)
        }

        /// Large title (26pt base) - scales with .title
        nonisolated static var titleLarge: Font {
            .system(.title, design: .rounded, weight: .bold)
        }

        /// Header (24pt base) - scales with .title2
        /// Uses .bold for confident section boundaries (#9)
        nonisolated static var header: Font {
            .system(.title2, design: .rounded, weight: .bold)
        }

        /// Medium title (20pt base) - scales with .title3
        /// Uses .bold for confident section boundaries (#9)
        nonisolated static var titleMedium: Font {
            .system(.title3, design: .rounded, weight: .bold)
        }

        /// Small title (18pt base) - scales with .headline
        nonisolated static var titleSmall: Font {
            .system(.headline, design: .rounded, weight: .semibold)
        }

        /// Callout (16pt base) - scales with .callout
        /// Uses .default design + .medium weight (#5, #11)
        nonisolated static var callout: Font {
            .system(.callout, design: .default, weight: .medium)
        }

        /// Body text (14pt base) - scales with .subheadline
        /// Uses .default (SF Pro) design for reading comfort (#5)
        nonisolated static var body: Font {
            .system(.subheadline, design: .default)
        }

        /// Body text with semibold weight
        nonisolated static var bodySemibold: Font {
            .system(.subheadline, design: .default, weight: .semibold)
        }

        /// Caption (13pt base) - scales with .footnote
        /// Uses .default design + .light weight for clear separation from body (#5, #8)
        nonisolated static var caption: Font {
            .system(.footnote, design: .default, weight: .light)
        }

        /// Small caption (11pt base) - scales with .caption2
        /// Uses .default design + .light weight (#5, #8)
        nonisolated static var captionSmall: Font {
            .system(.caption2, design: .default, weight: .light)
        }

        /// Small caption with semibold weight
        nonisolated static var captionSmallSemibold: Font {
            .system(.caption2, design: .default, weight: .semibold)
        }

        /// Caption with semibold weight
        nonisolated static var captionSemibold: Font {
            .system(.footnote, design: .default, weight: .semibold)
        }

        /// Callout with semibold weight
        nonisolated static var calloutSemibold: Font {
            .system(.callout, design: .default, weight: .semibold)
        }

        /// Callout with bold weight
        nonisolated static var calloutBold: Font {
            .system(.callout, design: .default, weight: .bold)
        }

        /// Body text with bold weight
        nonisolated static var bodyBold: Font {
            .system(.subheadline, design: .default, weight: .bold)
        }

        // MARK: - Expanded Weight Palette (#1-4)

        /// Small caption with light weight - for the most receded text
        nonisolated static var captionSmallLight: Font {
            .system(.caption2, design: .default, weight: .light)
        }

    }
    
    // MARK: - Shadow Styles
    
    /// Standardized shadow styles for consistent depth and elevation
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        /// Subtle shadow for slight elevation
        static let subtle = ShadowStyle(
            color: .black.opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
        
        /// Medium shadow for cards and elevated elements
        static let medium = ShadowStyle(
            color: .black.opacity(0.12),
            radius: 12,
            x: 0,
            y: 6
        )
        
        /// Strong shadow for modals and overlays
        static let strong = ShadowStyle(
            color: .black.opacity(UIConstants.OpacityConstants.moderate),
            radius: 24,
            x: 0,
            y: 12
        )
    }

    // MARK: - Semantic Style Tokens (#24)
    // Purpose-named font tokens that encode intent rather than appearance.
    // Use these for new code instead of choosing between caption/captionSemibold/captionSmall.

    enum SemanticFont {
        /// Timestamps, "3 days ago", "last updated", relative dates
        nonisolated static var metadata: Font {
            .system(.caption2, design: .default, weight: .light)
        }

        /// Form labels, field names, row labels
        nonisolated static var label: Font {
            .system(.callout, design: .default, weight: .medium)
        }

        /// Form values, data points, row values — rounded to match title hierarchy
        nonisolated static var value: Font {
            .system(.headline, design: .rounded, weight: .semibold)
        }

        /// Hero numbers on dashboards, large stats — rounded for display impact
        nonisolated static var stat: Font {
            .system(.largeTitle, design: .rounded, weight: .heavy)
        }

    }

    // MARK: - Surface Colors

    /// Platform-aware semantic surface colors. Use these instead of raw
    /// `NSColor`/`UIColor` references when filling pane and card backgrounds.
    enum Colors {
        /// Primary pane background. Maps to window background on macOS,
        /// secondary system background on iOS.
        nonisolated static var paneBackground: Color {
            #if os(macOS)
            return Color(NSColor.windowBackgroundColor)
            #else
            return Color(uiColor: .secondarySystemBackground)
            #endif
        }

        /// Background for a control-like surface that sits directly on a
        /// pane: sidebars, insight cards, list cards. Maps to control
        /// background on macOS, plain system background on iOS.
        ///
        /// Not the same pair as `Color.controlBackgroundColor()`, which
        /// takes the *secondary* system background on iOS.
        nonisolated static var controlBackground: Color {
            #if os(macOS)
            return Color(NSColor.controlBackgroundColor)
            #else
            return Color(uiColor: .systemBackground)
            #endif
        }

    }
}
