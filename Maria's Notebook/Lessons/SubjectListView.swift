// SubjectListView.swift
// Column 1 of the 3-column NavigationSplitView: Displays all subjects as a list.
// Subjects are derived from existing CDLesson data using LessonsViewModel.

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SubjectListView: View {
    let subjects: [String]
    let selectedSubject: String?
    let lessonCounts: [String: Int]
    let onSelectSubject: (String?) -> Void
    var onRenameSubject: ((String) -> Void)?

    var body: some View {
        List(selection: Binding(
            get: { selectedSubject },
            set: { onSelectSubject($0) }
        )) {
            ForEach(subjects, id: \.self) { subject in
                SubjectListRow(subject: subject, lessonCount: lessonCounts[subject] ?? 0)
                    .tag(subject)
                    .contextMenu {
                        Button {
                            onSelectSubject(subject)
                        } label: {
                            Label("View Lessons", systemImage: SFSymbol.Education.book)
                        }

                        if let onRename = onRenameSubject {
                            Button {
                                onRename(subject)
                            } label: {
                                Label("Rename Subject", systemImage: SFSymbol.Education.pencil)
                            }
                        }

                        Divider()

                        Button {
                            copySubjectName(subject)
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Subjects")
    }

    private func copySubjectName(_ subject: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(subject, forType: .string)
        #else
        UIPasteboard.general.string = subject
        #endif
    }
}

/// A row component for displaying a subject in a list view.
/// Shows the subject's icon (colored circle with subject-specific glyph), name, and lesson count.
/// Design matches StudentListRow for visual consistency across the app.
struct SubjectListRow: View {
    let subject: String
    let lessonCount: Int

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    /// Returns an SF Symbol name that best represents the subject
    private var subjectIcon: String {
        let key = subject.lowercased().trimmed()

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
            // Icon circle with subject-specific glyph (matching StudentListRow avatar style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [subjectColor.opacity(UIConstants.OpacityConstants.heavy), subjectColor]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 24
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: subjectIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Name and lesson count
            VStack(alignment: .leading, spacing: 2) {
                Text(subject)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                // CDLesson count as secondary text
                HStack(spacing: 4) {
                    Circle().fill(subjectColor).frame(width: 6, height: 6)
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
