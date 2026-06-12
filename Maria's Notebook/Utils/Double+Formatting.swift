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
    
}
