import SwiftUI

/// Sheet showing tardy counts per student over a selected date range.
struct AttendanceTardyReport: View {
    var body: some View {
        AttendanceStatusReport(config: .tardy)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceTardyReportPreview: View {
    var body: some View {
        AttendanceTardyReport()
            .previewEnvironment()
    }
}

#Preview {
    AttendanceTardyReportPreview()
}
