import SwiftUI

extension Image {
    /// Builds a system-symbol image, substituting a fallback when the name
    /// is empty. Empty symbol names log an "Invalid Configuration" SwiftUI
    /// fault on every render — every entity-backed icon string should flow
    /// through here so blank values can't reach `Image(systemName:)`.
    static func safeSymbol(
        _ name: String,
        fallback: String = "questionmark.square.dashed"
    ) -> Image {
        Image(systemName: name.isEmpty ? fallback : name)
    }
}
