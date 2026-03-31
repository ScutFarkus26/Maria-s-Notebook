import SwiftUI
import CoreData

struct WorkCheckInRow: View {
    let checkIn: WorkCheckIn
    let onEditNote: (WorkCheckIn) -> Void
    let onSetStatus: (UUID, WorkCheckInStatus) -> Void
    let onDelete: (WorkCheckIn) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                checkInHeader

                if hasNotes {
                    checkInNote
                }
            }

            Spacer()

            actionsMenu
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onEditNote(checkIn)
            } label: {
                Label("Add/Edit Note", systemImage: "note.text")
            }

            Divider()

            // Status change submenu
            Menu {
                ForEach(WorkCheckInStatus.allCases, id: \.self) { status in
                    Button {
                        onSetStatus(checkIn.id ?? UUID(), status)
                    } label: {
                        Label(
                            status.menuActionLabel,
                            systemImage: checkIn.status == status
                                ? "checkmark" : status.iconName
                        )
                    }
                    .disabled(checkIn.status == status)
                }
            } label: {
                Label("Set Status", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button(role: .destructive) {
                onDelete(checkIn)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var statusIcon: some View {
        Image(systemName: checkIn.status.iconName)
            .foregroundStyle(checkIn.status.color)
            .font(.system(size: 18))
    }
    
    private var checkInHeader: some View {
        HStack(spacing: 6) {
            Text((checkIn.date ?? Date()).formatted(date: .abbreviated, time: .omitted))
                .font(AppTheme.ScaledFont.bodySemibold)
            
            let purposeText = checkIn.purpose.trimmed()
            if !purposeText.isEmpty {
                Text("|")
                    .foregroundStyle(.secondary)
                Text(purposeText)
                    .font(AppTheme.ScaledFont.bodySemibold)
            }
        }
    }
    
    @ViewBuilder
    private var checkInNote: some View {
        let notesList = (checkIn.notes?.allObjects as? [CDNote]) ?? []
        VStack(alignment: .leading, spacing: 4) {
            if !notesList.isEmpty {
                ForEach(notesList.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }, id: \.id) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Notes:")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                        Text(note.body)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    private var hasNotes: Bool {
        !checkIn.latestUnifiedNoteText.trimmed().isEmpty
    }
    
    private var actionsMenu: some View {
        Menu {
            Button {
                onEditNote(checkIn)
            } label: {
                Label("Add/Edit Note", systemImage: "note.text")
            }

            Divider()

            ForEach(WorkCheckInStatus.allCases, id: \.self) { status in
                Button {
                    onSetStatus(checkIn.id ?? UUID(), status)
                } label: {
                    Label(status.menuActionLabel, systemImage: status.iconName)
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete(checkIn)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}
