//
//  TimeInterval+Formatting.swift
//  Maria's Notebook
//
//  Extensions for formatting TimeInterval values consistently
//

import Foundation

extension TimeInterval {
    /// Formats the time interval as a duration string with seconds
    /// - Returns: Formatted string (e.g., "1.234s")
    var formattedAsDuration: String {
        String(format: FormattingConstants.threeDecimal, self) + "s"
    }
    
    /// Formats the time interval as a duration string with single decimal
    /// - Returns: Formatted string (e.g., "1.2s")
    var formattedAsShortDuration: String {
        String(format: FormattingConstants.singleDecimal, self) + "s"
    }
}
