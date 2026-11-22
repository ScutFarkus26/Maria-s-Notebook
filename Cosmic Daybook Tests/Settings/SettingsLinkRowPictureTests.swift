import SwiftUI
import Testing
@testable import CosmicDaybook

/// Settings' link rows at the largest text sizes (plan "Tide list clean-up
/// 2026-11", Phase 4): Match Names wrapped letter by letter. Drawn from the
/// real row inside the real card with `ImageRenderer`; with
/// `SETTINGS_ROW_SHOT_DIR` set (pass `TEST_RUNNER_SETTINGS_ROW_SHOT_DIR=<folder>`
/// to the run) each picture is saved there, and the plan keeps them in
/// `docs/Pictures/Settings link rows/`.
@Suite("Settings link rows at large text sizes")
@MainActor
struct SettingsLinkRowPictureTests {
    /// iPhone 17's width less the pane's padding on each side, and a narrow
    /// column (Settings beside its list in a narrow iPad window).
    static let widths: [(name: String, points: CGFloat)] = [("phone", 402 - 2 * 16), ("narrow", 240)]

    private var folder: URL? {
        ProcessInfo.processInfo.environment["SETTINGS_ROW_SHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func card(_ size: DynamicTypeSize, old: Bool) -> some View {
        SettingsGroup(.attendanceEmail) {
            VStack(alignment: .leading, spacing: 12) {
                if old {
                    OldSettingsLinkRow(title: "Match Names", systemImage: "person.2.badge.gearshape")
                    OldSettingsLinkRow(
                        title: "Carried-over year plans", systemImage: "calendar.badge.exclamationmark", detail: "12"
                    )
                    OldSettingsLinkRow(title: "Sync history", systemImage: "clock.arrow.circlepath")
                } else {
                    SettingsLinkRow(title: "Match Names", systemImage: "person.2.badge.gearshape")
                    SettingsLinkRow(
                        title: "Carried-over year plans", systemImage: "calendar.badge.exclamationmark", detail: "12"
                    )
                    SettingsLinkRow(title: "Sync history", systemImage: "clock.arrow.circlepath")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .environment(\.dynamicTypeSize, size)
    }

    @Test("The rows draw before and after, at the default and the accessibility sizes", arguments: [
        DynamicTypeSize.large, .accessibility1, .accessibility3, .accessibility5
    ])
    func rowsDraw(size: DynamicTypeSize) throws {
        for width in Self.widths {
            for old in [true, false] {
                let name = "\(old ? "Before" : "After") - \(size) - \(width.name)"
                let data = try #require(
                    LessonTimePictures.png(card(size, old: old), scheme: .light, width: width.points)
                )
                if let folder {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: folder.appendingPathComponent("\(name).png"))
                }
                #expect(!data.isEmpty)
            }
        }
    }

    @Test("A row stacks its words only at accessibility sizes")
    func stacksAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            #expect(SettingsLinkRow.stacks(at: size) == size.isAccessibilitySize, "\(size)")
        }
    }
}

/// `SettingsLinkRow` as it was before this fix, kept only to draw the
/// "before" pictures beside the new row.
private struct OldSettingsLinkRow: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
    }
}
