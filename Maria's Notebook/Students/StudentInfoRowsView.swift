import SwiftUI
import CoreData

struct StudentInfoRowsView: View {
    let birthdayText: String
    let startDateText: String?
    let ageText: String
    let gradeText: String

    var body: some View {
        VStack(spacing: 14) {
            if !birthdayText.isEmpty {
                infoRow(icon: "calendar", title: "Birthday", value: birthdayText)
            }
            if let start = startDateText, !start.isEmpty {
                infoRow(icon: "calendar.badge.clock", title: "Start Date", value: start)
            }
            if !ageText.isEmpty {
                infoRow(icon: "gift", title: "Age", value: ageText)
            }
            if !gradeText.isEmpty {
                infoRow(icon: "graduationcap", title: "Florida Grade Equivalent", value: gradeText)
            }
        }
        .padding(.horizontal, 8)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(AppTheme.ScaledFont.titleSmall)
        }
    }
}
