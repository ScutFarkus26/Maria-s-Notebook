import SwiftUI

@MainActor
extension Binding where Value: MutableCollection & RangeReplaceableCollection,
                       Value.Element: Identifiable,
                       Value.Index == Int {
    /// Returns a `Binding` to a property of an `Identifiable` element within
    /// the array, looked up by stable id. Reads return `defaultValue` and
    /// writes are no-ops if the element has been removed — preventing the
    /// index-out-of-range crash that occurs when AppKit defers
    /// `controlTextDidEndEditing` past a mutation that shrinks the array.
    func element<T>(
        id: Value.Element.ID,
        default defaultValue: T,
        _ keyPath: WritableKeyPath<Value.Element, T>
    ) -> Binding<T> {
        // nonisolated(unsafe) locals satisfy the @Sendable closure requirements for
        // Binding(get:set:) while remaining safe — these values are only accessed on
        // the MainActor, as enforced by the @MainActor extension annotation.
        nonisolated(unsafe) let capturedSelf = self
        nonisolated(unsafe) let capturedId = id
        nonisolated(unsafe) let capturedDefault = defaultValue
        nonisolated(unsafe) let capturedKeyPath = keyPath
        return Binding<T>(
            get: {
                capturedSelf.wrappedValue
                    .first(where: { $0.id == capturedId })?[keyPath: capturedKeyPath]
                    ?? capturedDefault
            },
            set: { newValue in
                if let idx = capturedSelf.wrappedValue.firstIndex(where: { $0.id == capturedId }) {
                    capturedSelf.wrappedValue[idx][keyPath: capturedKeyPath] = newValue
                }
            }
        )
    }
}
