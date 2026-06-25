import Foundation
import CryptoKit

extension Data {
    /// Converts data to a hexadecimal string representation
    /// - Returns: Lowercase hexadecimal string (e.g., "0f3a4b")
    var hexString: String {
        map { String(format: FormattingConstants.twoDigitHex, $0) }.joined()
    }
}
