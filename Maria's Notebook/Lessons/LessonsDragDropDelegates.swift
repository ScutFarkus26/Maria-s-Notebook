import SwiftUI

public struct SubjectDropDelegate: DropDelegate {
    let index: Int
    let currentItems: [String]
    @Binding var dragState: (from: Int?, to: Int?)
    let onReorder: (Int, Int) -> Void

    public init(index: Int, currentItems: [String], dragState: Binding<(from: Int?, to: Int?)>, onReorder: @escaping (Int, Int) -> Void) {
        self.index = index
        self.currentItems = currentItems
        self._dragState = dragState
        self.onReorder = onReorder
    }

    public func validateDrop(info: DropInfo) -> Bool { true }
    public func dropEntered(info: DropInfo) {
        guard let from = dragState.from, from != index else { return }
        dragState.to = index
    }
    public func performDrop(info: DropInfo) -> Bool {
        guard let from = dragState.from, let to = dragState.to else { dragState = (nil, nil); return false }
        dragState = (nil, nil)
        if from != to { onReorder(from, to) }
        return true
    }
}

public struct GroupDropDelegate: DropDelegate {
    let subject: String
    let index: Int
    let currentItems: [String]
    @Binding var dragState: (from: Int?, to: Int?)
    let onReorder: (Int, Int) -> Void

    public init(subject: String, index: Int, currentItems: [String], dragState: Binding<(from: Int?, to: Int?)>, onReorder: @escaping (Int, Int) -> Void) {
        self.subject = subject
        self.index = index
        self.currentItems = currentItems
        self._dragState = dragState
        self.onReorder = onReorder
    }

    public func validateDrop(info: DropInfo) -> Bool { true }
    public func dropEntered(info: DropInfo) {
        guard let from = dragState.from, from != index else { return }
        dragState.to = index
    }
    public func performDrop(info: DropInfo) -> Bool {
        guard let from = dragState.from, let to = dragState.to else { dragState = (nil, nil); return false }
        dragState = (nil, nil)
        if from != to { onReorder(from, to) }
        return true
    }
}
