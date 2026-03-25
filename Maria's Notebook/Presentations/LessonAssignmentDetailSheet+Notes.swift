import SwiftUI
import SwiftData
import OSLog

// MARK: - Notes Section

extension LessonAssignmentDetailSheet {

    @ViewBuilder
    func unifiedNoteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note body first (like WorkDetailView)
            Text(note.body)
                .font(AppTheme.ScaledFont.body)
                .fixedSize(horizontal: false, vertical: true)

            // Display image if available
            if let imagePath = note.imagePath {
                AsyncCachedImage(filename: imagePath)
                    .frame(maxWidth: 300, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Metadata row
            HStack(spacing: 8) {
                // Tag badges
                if !note.tags.isEmpty {
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                Text(note.createdAt, style: .date)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    noteBeingEdited = note
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button {
                noteBeingEdited = note
            } label: {
                Label("Edit Note", systemImage: SFSymbol.Education.pencil)
            }
        }
    }

    @MainActor
    func reloadNotes() {
        guard let assignment else { return }

        // Load unified Note objects from relationship
        // Refresh the assignment object to get updated relationships
        let targetID = assignment.id
        var descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate<LessonAssignment> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        do {
            if let refreshed = try modelContext.fetch(descriptor).first {
                if let notes = refreshed.unifiedNotes {
                    self.unifiedNotes = Array(notes)
                } else {
                    self.unifiedNotes = []
                }
            } else {
                self.unifiedNotes = []
            }
        } catch {
            Self.logger.warning("Failed to fetch refreshed assignment: \(error)")
            self.unifiedNotes = []
        }
    }
}
