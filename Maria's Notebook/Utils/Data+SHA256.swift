import Foundation
import CryptoKit

extension Data {
    /// Computes the SHA256 hash of the data and returns it as a hexadecimal string
    var sha256Hex: String {
        SHA256.hash(data: self)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
