//
//  Double+Formatting.swift
//  Maria's Notebook
//
//  Extensions for formatting Double values consistently throughout the app
//

import Foundation

extension Double {
    /// Formats a score with specified maximum value (e.g., "3.5/5")
    /// - Parameter outOf: The maximum value for the score (default: 5)
    /// - Returns: Formatted string representation of the score
    func formatAsScore(outOf max: Int = 5) -> String {
        String(format: FormattingConstants.singleDecimal, self) + "/\(max)"
    }
    
    /// Formats a value as a percentage with specified decimal places
    /// - Parameter decimals: Number of decimal places to show (default: 1)
    /// - Returns: Formatted percentage string (e.g., "85.5%")
    func formatAsPercentage(decimals: Int = 1) -> String {
        let formatString = "%.\(decimals)f%%"
        return String(format: formatString, self * 100)
    }
}
