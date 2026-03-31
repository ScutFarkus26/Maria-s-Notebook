import SwiftUI
import CoreData

struct ScheduledCheckInsListSection: View {
    let checkIns: [CDWorkCheckIn]
    let onEditNote: (CDWorkCheckIn) -> Void
    let onSetStatus: (UUID, WorkCheckInStatus) -> Void
    let onDelete: (CDWorkCheckIn) -> Void
    
    @State private var selectedCheckInForNote: CDWorkCheckIn?
    
    private var sortedCheckIns: [CDWorkCheckIn] {
        checkIns.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "checklist", title: "Scheduled Check-Ins")
            
            if sortedCheckIns.isEmpty {
                emptyState
            } else {
                checkInsList
            }
        }
    }
    
    private var emptyState: some View {
        Text("No check-ins scheduled yet.")
            .foregroundStyle(.secondary)
            .font(AppTheme.ScaledFont.body)
            .italic()
    }
    
    private var checkInsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedCheckIns, id: \.objectID) { checkIn in
                WorkCheckInRow(
                    checkIn: checkIn,
                    onEditNote: { handleEditNote($0) },
                    onSetStatus: onSetStatus,
                    onDelete: onDelete
                )
            }
        }
        .sheet(item: $selectedCheckInForNote) { checkIn in
            WorkCheckInNoteEditorWrapper(checkIn: checkIn)
        }
    }
    
    private func handleEditNote(_ checkIn: CDWorkCheckIn) {
        // Use new UnifiedNoteEditor system
        selectedCheckInForNote = checkIn
        // Also call legacy callback for backward compatibility (in case parent view needs to do something)
        onEditNote(checkIn)
    }
}
