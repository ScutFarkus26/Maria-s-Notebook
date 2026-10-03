// AlbumSummarySheet.swift
// Lesson summary sheet

import SwiftUI

@Observable
final class AlbumSummaryState: Identifiable {
    let id = UUID()
    let lesson: AlbumLessonRef
    var result: String?
    var error: String?

    init(lesson: AlbumLessonRef) { self.lesson = lesson }
}

struct AlbumSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: AlbumSummaryState
    let album: Album
    let saveAsNote: (String, AlbumLessonRef) -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(state.lesson.title, systemImage: "sparkles")
                .font(.title3.bold())
            Divider()
            Group {
                if let error = state.error {
                    Text(error).foregroundStyle(.red)
                } else if let result = state.result {
                    ScrollView {
                        Text(markdown(result))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Summarizing on device…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 200)
            Divider()
            HStack {
                Text("Generated on device by Apple Intelligence — double-check against the album.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let result = state.result {
                    Button(saved ? "Saved" : "Save as Note") {
                        saveAsNote(result, state.lesson)
                        saved = true
                    }
                    .disabled(saved)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 380)
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
