// AppTheme+Spacing.swift
// Spacing constants for consistent layout across the app

import SwiftUI

extension AppTheme {
    /// Standardized spacing values for consistent layout.
    enum Spacing {
        /// 4pt - Extra small spacing for tight layouts
        static let xsmall: CGFloat = 4

        /// 8pt - Small spacing for compact elements
        static let small: CGFloat = 8

        /// 12pt - Between small and medium
        static let compact: CGFloat = 12

        /// 16pt - Standard medium spacing
        static let medium: CGFloat = 16

        /// 24pt - Large spacing for section gaps
        static let large: CGFloat = 24

        /// 32pt - Extra large spacing for major sections
        static let xlarge: CGFloat = 32

        /// 48pt - Used for major layout divisions
        static let xxlarge: CGFloat = 48
    }
}
