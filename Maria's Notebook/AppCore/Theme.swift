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
    // Note: All properties marked nonisolated to allow access from Sendable closures (e.g., PhotosPicker)
    enum ScaledFont {
        /// Extra large title (32pt base) - scales with .largeTitle
        nonisolated static var titleXLarge: Font {
            .system(.largeTitle, design: .rounded, weight: .bold)
        }

        /// Large title (26pt base) - scales with .title
        nonisolated static var titleLarge: Font {
            .system(.title, design: .rounded, weight: .bold)
        }

        /// Header (24pt base) - scales with .title2
        nonisolated static var header: Font {
            .system(.title2, design: .rounded, weight: .semibold)
        }

        /// Medium title (20pt base) - scales with .title3
        nonisolated static var titleMedium: Font {
            .system(.title3, design: .rounded, weight: .semibold)
        }

        /// Small title (18pt base) - scales with .headline
        nonisolated static var titleSmall: Font {
            .system(.headline, design: .rounded, weight: .semibold)
        }

        /// Callout (16pt base) - scales with .callout
        nonisolated static var callout: Font {
            .system(.callout, design: .rounded)
        }

        /// Body text (14pt base) - scales with .subheadline
        nonisolated static var body: Font {
            .system(.subheadline, design: .rounded)
        }

        /// Body text with semibold weight
        nonisolated static var bodySemibold: Font {
            .system(.subheadline, design: .rounded, weight: .semibold)
        }

        /// Caption (13pt base) - scales with .footnote
        nonisolated static var caption: Font {
            .system(.footnote, design: .rounded)
        }

        /// Small caption (11pt base) - scales with .caption2
        nonisolated static var captionSmall: Font {
            .system(.caption2, design: .rounded)
        }

        /// Small caption with semibold weight
        nonisolated static var captionSmallSemibold: Font {
            .system(.caption2, design: .rounded, weight: .semibold)
        }

        /// Caption with semibold weight
        nonisolated static var captionSemibold: Font {
            .system(.footnote, design: .rounded, weight: .semibold)
        }

        /// Callout with semibold weight
        nonisolated static var calloutSemibold: Font {
            .system(.callout, design: .rounded, weight: .semibold)
        }

        /// Callout with bold weight
        nonisolated static var calloutBold: Font {
            .system(.callout, design: .rounded, weight: .bold)
        }

        /// Body text with bold weight
        nonisolated static var bodyBold: Font {
            .system(.subheadline, design: .rounded, weight: .bold)
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
            color: .black.opacity(0.2),
            radius: 24,
            x: 0,
            y: 12
        )
    }

}

// MARK: - Font Extension for Easy Migration
extension Font {
    /// Creates a rounded font that scales with Dynamic Type
    /// Use this for migrating from fixed-size fonts to scaled fonts
    static func scaledRounded(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .rounded, weight: weight)
    }
}

// MARK: - View Extension for Shadow Styles
extension View {
    /// Apply a standardized shadow style
    func shadow(_ style: AppTheme.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - iOS 26 Liquid Glass Preparation
// When targeting iOS 26+, consider replacing CardBackgroundModifier and SubtleCardModifier
// backgrounds with the new .glassEffect() modifier for Apple's Liquid Glass design language.
// The ScaledFont system, opacity constants, and shadow styles are already well-structured
// for a smooth transition to the new visual language.
