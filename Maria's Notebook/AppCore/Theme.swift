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
    enum ScaledFont {
        /// Extra large title (32pt base) - scales with .largeTitle
        static var titleXLarge: Font {
            .system(.largeTitle, design: .rounded, weight: .bold)
        }

        /// Large title (26pt base) - scales with .title
        static var titleLarge: Font {
            .system(.title, design: .rounded, weight: .bold)
        }

        /// Header (24pt base) - scales with .title2
        static var header: Font {
            .system(.title2, design: .rounded, weight: .semibold)
        }

        /// Medium title (20pt base) - scales with .title3
        static var titleMedium: Font {
            .system(.title3, design: .rounded, weight: .semibold)
        }

        /// Small title (18pt base) - scales with .headline
        static var titleSmall: Font {
            .system(.headline, design: .rounded, weight: .semibold)
        }

        /// Callout (16pt base) - scales with .callout
        static var callout: Font {
            .system(.callout, design: .rounded)
        }

        /// Body text (14pt base) - scales with .subheadline
        static var body: Font {
            .system(.subheadline, design: .rounded)
        }

        /// Body text with semibold weight
        static var bodySemibold: Font {
            .system(.subheadline, design: .rounded, weight: .semibold)
        }

        /// Caption (13pt base) - scales with .footnote
        static var caption: Font {
            .system(.footnote, design: .rounded)
        }

        /// Small caption (11pt base) - scales with .caption2
        static var captionSmall: Font {
            .system(.caption2, design: .rounded)
        }

        /// Small caption with semibold weight
        static var captionSmallSemibold: Font {
            .system(.caption2, design: .rounded, weight: .semibold)
        }
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
