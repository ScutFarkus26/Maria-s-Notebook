import SwiftUI

struct ScheduledCheckInsListSection: View {
    let checkIns: [WorkCheckIn]
    let onEditNote: (WorkCheckIn) -> Void
    let onSetStatus: (UUID, WorkCheckInStatus) -> Void
    let onDelete: (WorkCheckIn) -> Void
    
    private var sortedCheckIns: [WorkCheckIn] {
        checkIns.sorted(by: { $0.date < $1.date })
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
            .font(.system(size: AppTheme.FontSize.body))
            .italic()
    }
    
    private var checkInsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedCheckIns, id: \.id) { checkIn in
                WorkCheckInRow(
                    checkIn: checkIn,
                    onEditNote: onEditNote,
                    onSetStatus: onSetStatus,
                    onDelete: onDelete
                )
            }
        }
    }
}
