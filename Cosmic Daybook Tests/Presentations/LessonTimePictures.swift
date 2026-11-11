import SwiftUI
@testable import CosmicDaybook

/// Pictures of the lesson-time views, drawn from the real views with
/// `ImageRenderer` so no app launches and no screen is needed. With
/// `LESSON_TIME_SHOT_DIR` set (pass it to a test run as
/// `TEST_RUNNER_LESSON_TIME_SHOT_DIR=<folder>`) each picture is also saved there
/// as `<name>-dark.png` or `<name>-light.png`; the plan keeps them in
/// `docs/Pictures/Lesson times/`.
///
/// Shared by the lesson-time phases (docs/Plans/Plan - Lesson times on cards.md):
/// the picker, the card chip, the sheet and Today. `ImageRenderer` draws a
/// `ScrollView` blank, so draw the content inside one, not the scroll view.
@MainActor
enum LessonTimePictures {
    static let folderVariable = "LESSON_TIME_SHOT_DIR"

    /// The folder pictures are saved to, or nil when the run didn't ask for them.
    static var folder: URL? {
        ProcessInfo.processInfo.environment[folderVariable].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The surface a picture is drawn on: close to a popover's in each scheme.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    /// `view` as PNG data in `scheme`, `width` points wide when given, at 3×.
    static func png(
        _ view: some View, scheme: ColorScheme, width: CGFloat? = nil, background: Color? = nil
    ) -> Data? {
        let framed = view
            .frame(width: width)
            .background(background ?? surface(scheme))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        #if os(macOS)
        guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    /// Draws `view` and, when the run asked for pictures, saves it as
    /// `<name>-dark.png` or `<name>-light.png`. Returns the PNG data either way.
    @discardableResult
    static func save(
        _ view: some View, named name: String, scheme: ColorScheme,
        width: CGFloat? = nil, background: Color? = nil
    ) throws -> Data? {
        let data = png(view, scheme: scheme, width: width, background: background)
        if let folder, let data {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = "\(name)-\(scheme == .dark ? "dark" : "light").png"
            try data.write(to: folder.appendingPathComponent(file))
        }
        return data
    }
}
