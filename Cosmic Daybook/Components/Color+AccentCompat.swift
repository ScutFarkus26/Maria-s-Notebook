import SwiftUI

// Compatibility shim so we can write `.foregroundStyle(.accent)`
extension ShapeStyle where Self == Color {
    static var accent: Color { .accentColor }
}
