import SwiftUI

enum AppTheme {
    // MARK: - Legacy Font Sizes (for reference/migration)
    // These static values are kept for backwards compatibility
    // Prefer using ScaledFont for new code to support Dynamic Type
    enum FontSize {
        static let titleLarge: CGFloat = 26
        static let titleMedium: CGFloat = 20
        static let body: CGFloat = 14
        static let titleXLarge: CGFloat = 32
        static let titleSmall: CGFloat = 18
        static let header: CGFloat = 24
        static let callout: CGFloat = 16
        static let caption: CGFloat = 13
        static let captionSmall: CGFloat = 11
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

        /// Body text with light weight - for long-form descriptions, observation notes
        nonisolated static var bodyLight: Font {
            .system(.subheadline, design: .default, weight: .light)
        }

        /// Caption with light weight - for tertiary metadata, timestamps, "last updated"
        nonisolated static var captionLight: Font {
            .system(.footnote, design: .default, weight: .light)
        }

        /// Small caption with light weight - for the most receded text
        nonisolated static var captionSmallLight: Font {
            .system(.caption2, design: .default, weight: .light)
        }

        /// Body text with medium weight - subtle emphasis without full semibold
        nonisolated static var bodyMedium: Font {
            .system(.subheadline, design: .default, weight: .medium)
        }

        /// Callout with medium weight - distinct from both regular and semibold
        nonisolated static var calloutMedium: Font {
            .system(.callout, design: .default, weight: .medium)
        }

        /// Large title with heavy weight - hero display text
        nonisolated static var titleXLargeHeavy: Font {
            .system(.largeTitle, design: .rounded, weight: .heavy)
        }

        /// Title with heavy weight - strong section anchors
        nonisolated static var titleLargeHeavy: Font {
            .system(.title, design: .rounded, weight: .heavy)
        }

        /// Headline with bold weight - stronger list item titles
        nonisolated static var titleSmallBold: Font {
            .system(.headline, design: .rounded, weight: .bold)
        }

        // MARK: - Serif Display Variants (#7)

        /// Serif display font for the largest titles — editorial, premium feel
        nonisolated static var displaySerif: Font {
            .system(.largeTitle, design: .serif, weight: .bold)
        }

        /// Serif title font for detail view headers
        nonisolated static var titleSerif: Font {
            .system(.title, design: .serif, weight: .semibold)
        }

        // MARK: - Monospaced Variants (#6)

        /// Full monospaced font for grid cells, codes, IDs
        nonisolated static var monoBody: Font {
            .system(.subheadline, design: .monospaced, weight: .medium)
        }

        /// Small monospaced font for dense data tables
        nonisolated static var monoCaption: Font {
            .system(.caption2, design: .monospaced, weight: .medium)
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
        
        /// Elevated shadow for floating elements
        static let elevated = ShadowStyle(
            color: .black.opacity(0.15),
            radius: 16,
            x: 0,
            y: 8
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

        /// Numeric data in grids/tables — monospaced digits for column alignment (#22)
        nonisolated static var tabularNumber: Font {
            .system(.subheadline, design: .default, weight: .medium).monospacedDigit()
        }

        /// Small numeric data in dense grids — heavier stroke at small sizes (#23)
        nonisolated static var denseGridCell: Font {
            .system(.caption2, design: .default, weight: .medium).monospacedDigit()
        }

        /// Chart axis labels and legend text
        nonisolated static var chartLabel: Font {
            .system(.caption2, design: .default, weight: .regular).monospacedDigit()
        }
    }

    // MARK: - Tracking (Letter Spacing) Constants (#12-14)

    /// Standardized letter-spacing values for typographic refinement
    enum Tracking {
        /// Tight tracking for large display titles (26pt+) — more refined, editorial feel (#13)
        nonisolated static let display: CGFloat = -0.3

        /// Standard tracking — no adjustment (default)
        nonisolated static let standard: CGFloat = 0

        /// Slightly wider tracking for small text in pills/badges (#14)
        nonisolated static let badge: CGFloat = 0.2

        /// Wide tracking for uppercase section labels / overline text (#12)
        nonisolated static let overline: CGFloat = 0.8

        /// Extra wide tracking for very small uppercase labels
        nonisolated static let wideUppercase: CGFloat = 1.0
    }
}
