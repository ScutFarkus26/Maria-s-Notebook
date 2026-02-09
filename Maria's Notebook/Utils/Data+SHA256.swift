import Foundation
import CryptoKit

extension Data {
    /// Computes the SHA256 hash of the data and returns it as a hexadecimal string
    var sha256Hex: String {
        SHA256.hash(data: self)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
    
    /// Converts data to a hexadecimal string representation
    /// - Returns: Lowercase hexadecimal string (e.g., "0f3a4b")
    var hexString: String {
        map { String(format: FormattingConstants.twoDigitHex, $0) }.joined()
    }
    
    /// Converts data to an uppercase hexadecimal string representation
    /// - Returns: Uppercase hexadecimal string (e.g., "0F3A4B")
    var hexStringUppercase: String {
        map { String(format: FormattingConstants.twoDigitHexUppercase, $0) }.joined()
    }
}
