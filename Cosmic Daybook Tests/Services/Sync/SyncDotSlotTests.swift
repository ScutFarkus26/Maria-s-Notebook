import SwiftUI
import Testing
@testable import CosmicDaybook

// The sync dot keeps its slot: showing or hiding it must not move the items beside it
// (2026-10-13 Lessons and Work changes, #4). Rendered with ImageRenderer so no app launches.

private struct XKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ToolbarMock: View {
    let state: SyncDotState

    var body: some View {
        HStack(spacing: 8) {
            Text("Class").tracked("left")
            Image(systemName: "magnifyingglass").tracked("search")
            SyncDotView(state: state).tracked("dot")
            Text("Year").tracked("right")
        }
        .padding(12)
        .frame(width: 300, height: 44)
        .background(Color.white)
    }
}

private extension View {
    func tracked(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: XKey.self, value: [name: proxy.frame(in: .named("row"))])
        })
    }
}

@MainActor
private func layout(for state: SyncDotState, save: String? = nil) -> [String: CGRect] {
    var frames: [String: CGRect] = [:]
    let view = ToolbarMock(state: state)
        .coordinateSpace(name: "row")
        .onPreferenceChange(XKey.self) { frames = $0 }
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    #if os(macOS)
    let image = renderer.nsImage
    #else
    let image = renderer.uiImage
    #endif
    if let save, let image, let dir = ProcessInfo.processInfo.environment["SYNC_DOT_SHOT_DIR"] {
        #if os(macOS)
        let data = image.tiffRepresentation
        #else
        let data = image.pngData()
        #endif
        try? data?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(save).\(data == nil ? "x" : "png")"))
    }
    return frames
}

@MainActor
struct SyncDotSlotTests {
    @Test func neighborsStayPutWhetherTheDotIsShownOrNot() {
        let hidden = layout(for: .synced, save: "dot-hidden")
        let shown = layout(for: .syncing, save: "dot-shown")
        #expect(hidden["dot"] != nil)
        #expect(hidden["dot"]?.size == CGSize(width: 8, height: 8))
        for key in ["left", "search", "dot", "right"] {
            #expect(hidden[key] == shown[key], "\(key) moved")
        }
    }
}
