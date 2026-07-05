import SwiftUI
import CoreData

/// Meeting-notes section of `TopicDetailView`: lists existing notes and
/// provides the add-note form.
struct TopicMeetingNotesSection: View {
    let notes: [CDNote]
    @Binding var newNoteSpeaker: String
    @Binding var newNoteContent: String

    var onDelete: (CDNote) -> Void
    var onAdd: () -> Void

    var body: some View {
        GroupBox("Meeting Notes") {
            VStack(alignment: .leading, spacing: 10) {
                if notes.isEmpty {
                    Text("No notes yet.").foregroundStyle(.secondary)
                } else {
                    let sortedNotes: [CDNote] = notes.sorted {
                        ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
                    }
                    ForEach(sortedNotes) { n in
                        HStack(alignment: .top, spacing: 8) {
                            if let reporterName = n.reporterName, !reporterName.trimmed().isEmpty {
                                Text(reporterName).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(UIConstants.OpacityConstants.medium))
                                    )
                            }
                            Text(n.body).font(.subheadline)
                            Spacer()
                            Menu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDelete(n)
                                }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                        )
                    }
                }

                Divider().padding(.vertical, 4)

                TextField("Speaker (optional)", text: $newNoteSpeaker)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newNoteContent).frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )

                HStack {
                    Spacer()
                    Button("Add Note", action: onAdd)
                        .buttonStyle(.bordered)
                        .disabled(newNoteContent.trimmed().isEmpty)
                }
            }
        }
    }
}
