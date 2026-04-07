import SwiftUI
import CoreData
import OSLog

// MARK: - Notes Section

extension LessonAssignmentDetailSheet {

    @ViewBuilder
    func unifiedNoteRow(_ note: CDNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // CDNote body first (like WorkDetailView)
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
                if !note.tagsArray.isEmpty {
                    ForEach(note.tagsArray.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }

                Text(note.createdAt ?? Date(), style: .date)
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint), lineWidth: 1)
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

        // Load unified CDNote objects from relationship
        // Refresh the assignment object to get updated relationships
        guard let targetID = assignment.id else { return }
        let descriptor: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
        descriptor.predicate = NSPredicate(format: "id == %@", targetID as CVarArg)
        descriptor.fetchLimit = 1
        do {
            if let refreshed = try viewContext.fetch(descriptor).first {
                if let notes = refreshed.unifiedNotes?.allObjects as? [CDNote], !notes.isEmpty {
                    self.unifiedNotes = notes
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
