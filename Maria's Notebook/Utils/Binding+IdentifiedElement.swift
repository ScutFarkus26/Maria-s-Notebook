import SwiftUI

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
        Binding<T>(
            get: { self.wrappedValue.first(where: { $0.id == id })?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                if let idx = self.wrappedValue.firstIndex(where: { $0.id == id }) {
                    self.wrappedValue[idx][keyPath: keyPath] = newValue
                }
            }
        )
    }
}
