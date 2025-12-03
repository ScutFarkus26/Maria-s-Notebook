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
                
                if !checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
    }
    
    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .foregroundStyle(statusColor)
            .font(.system(size: 18))
    }
    
    private var statusIconName: String {
        switch checkIn.status {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .scheduled: return "clock"
        }
    }
    
    private var statusColor: Color {
        switch checkIn.status {
        case .completed: return .green
        case .skipped: return .red
        case .scheduled: return .orange
        }
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
    
    private var actionsMenu: some View {
        Menu {
            Button {
                onEditNote(checkIn)
            } label: {
                Label("Add/Edit Note", systemImage: "note.text")
            }
            
            Divider()
            
            Button {
                onSetStatus(checkIn.id, .completed)
            } label: {
                Label("Mark Completed", systemImage: "checkmark.circle")
            }
            
            Button {
                onSetStatus(checkIn.id, .scheduled)
            } label: {
                Label("Mark Scheduled", systemImage: "clock")
            }
            
            Button {
                onSetStatus(checkIn.id, .skipped)
            } label: {
                Label("Mark Skipped", systemImage: "xmark.circle")
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
