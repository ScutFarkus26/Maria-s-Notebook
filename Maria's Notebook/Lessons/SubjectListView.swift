// AreaListView.swift
// Column 1 of the 3-column NavigationSplitView: Displays all areas as a list.
// Areas are derived from existing CDLesson data using LessonsViewModel.

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AreaListView: View {
    let areas: [String]
    let selectedArea: String?
    let lessonCounts: [String: Int]
    let onSelectArea: (String?) -> Void
    var onRenameArea: ((String) -> Void)?

    var body: some View {
        List(selection: Binding(
            get: { selectedArea },
            set: { onSelectArea($0) }
        )) {
            ForEach(areas, id: \.self) { area in
                AreaListRow(area: area, lessonCount: lessonCounts[area] ?? 0)
                    .tag(area)
                    .contextMenu {
                        Button {
                            onSelectArea(area)
                        } label: {
                            Label("View Lessons", systemImage: SFSymbol.Education.book)
                        }

                        if let onRename = onRenameArea {
                            Button {
                                onRename(area)
                            } label: {
                                Label("Rename Area", systemImage: SFSymbol.Education.pencil)
                            }
                        }

                        Divider()

                        Button {
                            copyAreaName(area)
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Areas")
    }

    private func copyAreaName(_ area: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(area, forType: .string)
        #else
        UIPasteboard.general.string = area
        #endif
    }
}

/// A row component for displaying a area in a list view.
/// Shows the area's icon (colored circle with area-specific glyph), name, and lesson count.
/// Design matches StudentListRow for visual consistency across the app.
struct AreaListRow: View {
    let area: String
    let lessonCount: Int

    private var areaColor: Color {
        AppColors.color(forArea: area)
    }

    /// Returns an SF Symbol name that best represents the area
    private var areaIcon: String {
        let key = area.lowercased().trimmed()

        switch key {
        case "math", "mathematics":
            return "plus.forwardslash.minus"
        case "language", "language arts":
            return "textformat.abc"
        case "science":
            return "flask.fill"
        case "practical life":
            return "hands.sparkles.fill"
        case "sensorial":
            return "hand.point.up.fill"
        case "geography":
            return "globe.americas.fill"
        case "history":
            return "clock.fill"
        case "art":
            return "paintpalette.fill"
        case "music":
            return "music.note"
        case "grace & courtesy", "grace and courtesy":
            return "heart.fill"
        case "geometry":
            return "triangle.fill"
        case "botany":
            return "leaf.fill"
        case "zoology":
            return "pawprint.fill"
        case "reading":
            return "book.fill"
        case "writing":
            return "pencil"
        case "culture":
            return "building.columns.fill"
        case "spanish", "french", "german", "italian", "mandarin", "chinese":
            return "globe"
        default:
            return "book.closed.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon circle with area-specific glyph (matching StudentListRow avatar style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [areaColor.opacity(UIConstants.OpacityConstants.heavy), areaColor]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: areaIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Name and lesson count
            VStack(alignment: .leading, spacing: 2) {
                Text(area)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                // CDLesson count as secondary text
                HStack(spacing: 4) {
                    Circle().fill(areaColor).frame(width: 6, height: 6)
                    Text("\(lessonCount) \(lessonCount == 1 ? "lesson" : "lessons")")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
