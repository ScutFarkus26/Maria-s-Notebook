// KeyboardShortcutsHelpView.swift
// macOS keyboard shortcuts discoverability window

import SwiftUI

#if os(macOS)
struct KeyboardShortcutsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Keyboard Shortcuts")
                    .font(AppTheme.ScaledFont.titleLarge)
                    .padding(.bottom, 4)

                shortcutSection("Navigation", shortcuts: [
                    ShortcutItem(keys: "\u{2318}1", description: "Today"),
                    ShortcutItem(keys: "\u{2318}2", description: "Presentations"),
                    ShortcutItem(keys: "\u{2318}3", description: "Students"),
                    ShortcutItem(keys: "\u{2318}4", description: "Lessons"),
                    ShortcutItem(keys: "\u{2318}5", description: "Logs"),
                    ShortcutItem(keys: "\u{2318}6", description: "Attendance"),
                    ShortcutItem(keys: "\u{2318},", description: "Settings")
                ])

                shortcutSection("Create", shortcuts: [
                    ShortcutItem(keys: "\u{2318}N", description: "New CDLesson"),
                    ShortcutItem(keys: "\u{21E7}\u{2318}N", description: "New CDStudent"),
                    ShortcutItem(keys: "\u{2325}\u{2318}N", description: "New Work")
                ])

                shortcutSection("Import & Backup", shortcuts: [
                    ShortcutItem(keys: "\u{2318}I", description: "Import Lessons"),
                    ShortcutItem(keys: "\u{21E7}\u{2318}I", description: "Import Students"),
                    ShortcutItem(keys: "\u{2318}B", description: "Create Backup"),
                    ShortcutItem(keys: "\u{21E7}\u{2318}B", description: "Restore Data")
                ])

                shortcutSection("General", shortcuts: [
                    ShortcutItem(keys: "\u{2318}F", description: "Search"),
                    ShortcutItem(keys: "\u{2318}W", description: "Close Window"),
                    ShortcutItem(keys: "\u{2318}?", description: "Help")
                ])
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, idealWidth: 480, minHeight: 500, idealHeight: 600)
    }

    private func shortcutSection(_ title: String, shortcuts: [ShortcutItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.ScaledFont.titleSmall)
                .foregroundStyle(.secondary)

            ForEach(shortcuts) { shortcut in
                HStack {
                    Text(shortcut.keys)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(.secondary)

                    Text(shortcut.description)
                        .font(AppTheme.ScaledFont.body)

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}
#endif
