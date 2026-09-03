import SwiftUI

/// Sheet showing tardy counts per student over a selected date range.
struct AttendanceTardyReport: View {
    var body: some View {
        AttendanceStatusReport(config: .tardy)
    }
}

#Preview {
    AttendanceTardyReport()
        .previewEnvironment()
}
