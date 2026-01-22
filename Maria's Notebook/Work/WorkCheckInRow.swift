import SwiftUI

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
                .fill(Color.primary.opacity(0.04))
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
                        onSetStatus(checkIn.id, status)
                    } label: {
                        Label(status.menuActionLabel, systemImage: checkIn.status == status ? "checkmark" : status.iconName)
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
            Text(checkIn.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
            
            let purposeText = checkIn.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            if !purposeText.isEmpty {
                Text("|")
                    .foregroundStyle(.secondary)
                Text(purposeText)
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
        }
    }
    
    private var checkInNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show notes from the relationship (new system)
            if let notes = checkIn.notes, !notes.isEmpty {
                ForEach(notes.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Notes:")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(note.body)
                            .font(.system(size: AppTheme.FontSize.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
            // Fallback to legacy string field for backward compatibility
            else if !checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Notes:")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(checkIn.note)
                        .font(.system(size: AppTheme.FontSize.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }
    
    private var hasNotes: Bool {
        if let notes = checkIn.notes, !notes.isEmpty {
            return true
        }
        return !checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    onSetStatus(checkIn.id, status)
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
