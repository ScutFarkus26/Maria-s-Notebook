import SwiftUI
import Testing
@testable import CosmicDaybook

/// The Brewing mark itself, drawn with ImageRenderer so no app launches: it must not
/// look like plain Planned. With `BREWING_SHOT_DIR` set (pass it to a test run as
/// `TEST_RUNNER_BREWING_SHOT_DIR`) the key's marks are saved there, light and dark.
extension ChecklistBrewingTests {

    /// The ladder's marks as the key shows them, Brewing after Planned.
    private struct MarkRow: View {
        let scheme: ColorScheme

        var body: some View {
            HStack(spacing: 18) {
                ForEach(ChecklistDisplayStatus.allCases, id: \.self) { status in
                    item(ChecklistMark(status: status, size: 30), status == .notReady ? "Not yet" : status.label)
                    if status == .planned {
                        item(ChecklistMark(status: .planned, brewing: true, size: 30), "Brewing")
                    }
                }
            }
            .padding(20)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
        }

        private func item(_ mark: ChecklistMark, _ label: String) -> some View {
            VStack(spacing: 8) {
                mark
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func png(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        #if os(macOS)
        guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    @Test("The Brewing mark draws differently from plain Planned, in light and dark",
          arguments: [ColorScheme.light, .dark])
    func brewingMarkDraws(scheme: ColorScheme) throws {
        let planned = try #require(png(
            ChecklistMark(status: .planned, size: 30).padding(4).environment(\.colorScheme, scheme)
        ))
        let brewing = try #require(png(
            ChecklistMark(status: .planned, brewing: true, size: 30).padding(4).environment(\.colorScheme, scheme)
        ))
        #expect(planned != brewing)
        // Only Planned wears the dot: on another rung the flag draws nothing.
        let presented = try #require(png(ChecklistMark(status: .presented, size: 30).padding(4)))
        let flagged = try #require(png(ChecklistMark(status: .presented, brewing: true, size: 30).padding(4)))
        #expect(presented == flagged)

        if let dir = ProcessInfo.processInfo.environment["BREWING_SHOT_DIR"] {
            let name = scheme == .dark ? "brewing-marks-dark.png" : "brewing-marks-light.png"
            try png(MarkRow(scheme: scheme))?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }
}
