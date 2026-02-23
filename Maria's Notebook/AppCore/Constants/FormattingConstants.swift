//
//  FormattingConstants.swift
//  Maria's Notebook
//
//  Centralized formatting constants for string interpolation and display
//

import Foundation

enum FormattingConstants {
    // MARK: - Number Formatting
    
    /// Single decimal place format (e.g., "3.5")
    static let singleDecimal = "%.1f"
    
    /// Three decimal places for precision timing (e.g., "0.123")
    static let threeDecimal = "%.3f"
    
    /// No decimal places (e.g., "42")
    static let noDecimal = "%.0f"
    
    // MARK: - Date/Time Formatting
    
    /// Four-digit year with zero padding (e.g., "2024")
    static let fourDigitYear = "%04d"
    
    /// Two-digit month with zero padding (e.g., "03")
    static let twoDigitMonth = "%02d"
    
    // MARK: - Hash/Hex Formatting
    
    /// Two-digit hex format with zero padding (e.g., "0f")
    static let twoDigitHex = "%02x"
    
    /// Two-digit uppercase hex format with zero padding (e.g., "0F")
    static let twoDigitHexUppercase = "%02X"
}
