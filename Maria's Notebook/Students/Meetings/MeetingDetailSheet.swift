// MeetingDetailSheet.swift
// Full meeting detail presented as a sheet from Recent Meetings

import SwiftUI

struct MeetingDetailSheet: View {
    let meeting: CDStudentMeeting
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !meeting.reflection.trimmed().isEmpty {
                        DetailLine(title: "Reflection", text: meeting.reflection)
                    }

                    if !meeting.focus.trimmed().isEmpty {
                        DetailLine(title: "Focus", text: meeting.focus)
                    }

                    if !meeting.requests.trimmed().isEmpty {
                        DetailLine(title: "Requests", text: meeting.requests)
                    }

                    if !meeting.guideNotes.trimmed().isEmpty {
                        DetailLine(title: "Guide Notes", text: meeting.guideNotes)
                    }

                    if meeting.reflection.trimmed().isEmpty
                        && meeting.focus.trimmed().isEmpty
                        && meeting.requests.trimmed().isEmpty
                        && meeting.guideNotes.trimmed().isEmpty {
                        Text("No notes recorded")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(
                (meeting.date ?? Date()).formatted(date: .long, time: .omitted)
            )
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
