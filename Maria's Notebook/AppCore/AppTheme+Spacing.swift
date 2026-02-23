// AppTheme+Spacing.swift
// Spacing constants for consistent layout across the app

import SwiftUI

extension AppTheme {
    /// Standardized spacing values for consistent layout.
    enum Spacing {
        // MARK: - Core Spacing Scale
        
        /// 2pt - Extra extra small spacing for minimal gaps
        nonisolated static let xxsmall: CGFloat = 2
        
        /// 4pt - Extra small spacing for tight layouts
        nonisolated static let xsmall: CGFloat = 4
        
        /// 6pt - Alias for small spacing (status pills, tight elements)
        nonisolated static let xs: CGFloat = 4
        
        /// 6pt - Very small spacing
        nonisolated static let verySmall: CGFloat = 6

        /// 8pt - Small spacing for compact elements
        nonisolated static let small: CGFloat = 8
        
        /// 6pt - Alias for small spacing
        nonisolated static let sm: CGFloat = 6

        /// 12pt - Between small and medium
        nonisolated static let compact: CGFloat = 12
        
        /// 12pt - Alias for medium spacing
        static let md: CGFloat = 12

        /// 16pt - Standard medium spacing
        static let medium: CGFloat = 16
        
        /// 16pt - Alias for large spacing
        static let lg: CGFloat = 16

        /// 24pt - Large spacing for section gaps
        static let large: CGFloat = 24
        
        /// 24pt - Alias for extra large spacing
        static let xl: CGFloat = 24

        /// 32pt - Extra large spacing for major sections
        static let xlarge: CGFloat = 32
        
        /// 28pt - Alias for extra extra large spacing
        static let xxl: CGFloat = 28

        /// 48pt - Used for major layout divisions
        static let xxlarge: CGFloat = 48
        
        // MARK: - Semantic Spacing (specific use cases)
        
        /// 6pt - Horizontal padding for status pills
        static let statusPillHorizontal: CGFloat = 6
        
        /// 3pt - Vertical padding for status pills
        static let statusPillVertical: CGFloat = 3
        
        /// 12pt - Standard card padding
        static let cardPadding: CGFloat = 12
        
        /// 16pt - Spacing between sections
        static let sectionSpacing: CGFloat = 16
    }
}
