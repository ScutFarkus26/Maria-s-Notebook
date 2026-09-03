import SwiftUI

/// Sheet showing absence counts per student over a selected date range.
struct AttendanceAbsenceReport: View {
    var body: some View {
        AttendanceStatusReport(config: .absence)
    }
}

#Preview {
    AttendanceAbsenceReport()
        .previewEnvironment()
}
