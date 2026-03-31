import SwiftUI

struct ScheduleCheckInSection: View {
    @Binding var checkInDate: Date
    @Binding var checkInPurpose: String
    let onSchedule: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "calendar.badge.clock", title: "CDSchedule Check-In")
            
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: $checkInDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                
                TextField("Purpose (optional)", text: $checkInPurpose)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    onSchedule()
                } label: {
                    Label("CDSchedule Check-In", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
