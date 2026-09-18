import SwiftUI

/// Sheet showing absence counts per student over a selected date range.
struct AttendanceAbsenceReport: View {
    var body: some View {
        AttendanceStatusReport(config: .absence)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceAbsenceReportPreview: View {
    var body: some View {
        AttendanceAbsenceReport()
            .previewEnvironment()
    }
}

#Preview {
    AttendanceAbsenceReportPreview()
}
