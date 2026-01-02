import SwiftUI

struct LessonAgeSettingsView: View {
    @SyncedAppStorage("LessonAge.warningDays") private var warningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage("LessonAge.overdueDays") private var overdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage("LessonAge.freshColorHex") private var freshHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage("LessonAge.warningColorHex") private var warningHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage("LessonAge.overdueColorHex") private var overdueHex: String = LessonAgeDefaults.overdueColorHex

    @State private var freshColor: Color = ColorUtils.color(from: LessonAgeDefaults.freshColorHex)
    @State private var warningColor: Color = ColorUtils.color(from: LessonAgeDefaults.warningColorHex)
    @State private var overdueColor: Color = ColorUtils.color(from: LessonAgeDefaults.overdueColorHex)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure thresholds and colors for the lesson age indicator in Planning → Agenda.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Stepper(value: $warningDays, in: 0...30) {
                    Text("Warning starts at \(warningDays) school day\(warningDays == 1 ? "" : "s")")
                }
                Stepper(value: $overdueDays, in: 1...60) {
                    Text("Overdue after \(overdueDays) school day\(overdueDays == 1 ? "" : "s")")
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Fresh Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Fresh", selection: Binding(get: { freshColor }, set: { new in
                        freshColor = new
                        freshHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Warning Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Warning", selection: Binding(get: { warningColor }, set: { new in
                        warningColor = new
                        warningHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Overdue Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Overdue", selection: Binding(get: { overdueColor }, set: { new in
                        overdueColor = new
                        overdueHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
            }
        }
        .onAppear {
            // Initialize pickers from stored hex strings
            freshColor = ColorUtils.color(from: freshHex)
            warningColor = ColorUtils.color(from: warningHex)
            overdueColor = ColorUtils.color(from: overdueHex)
        }
    }
}

struct WorkAgeSettingsView: View {
    @SyncedAppStorage("WorkAge.warningDays") private var warningDays: Int = WorkAgeDefaults.warningDays
    @SyncedAppStorage("WorkAge.overdueDays") private var overdueDays: Int = WorkAgeDefaults.overdueDays
    @SyncedAppStorage("WorkAge.freshColorHex") private var freshHex: String = WorkAgeDefaults.freshColorHex
    @SyncedAppStorage("WorkAge.warningColorHex") private var warningHex: String = WorkAgeDefaults.warningColorHex
    @SyncedAppStorage("WorkAge.overdueColorHex") private var overdueHex: String = WorkAgeDefaults.overdueColorHex

    @State private var freshColor: Color = ColorUtils.color(from: WorkAgeDefaults.freshColorHex)
    @State private var warningColor: Color = ColorUtils.color(from: WorkAgeDefaults.warningColorHex)
    @State private var overdueColor: Color = ColorUtils.color(from: WorkAgeDefaults.overdueColorHex)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure thresholds and colors for the work age indicator in Planning → Work Agenda.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Stepper(value: $warningDays, in: 0...30) {
                    Text("Warning starts at \(warningDays) school day\(warningDays == 1 ? "" : "s")")
                }
                Stepper(value: $overdueDays, in: 1...60) {
                    Text("Overdue after \(overdueDays) school day\(overdueDays == 1 ? "" : "s")")
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Fresh Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Fresh", selection: Binding(get: { freshColor }, set: { new in
                        freshColor = new
                        freshHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Warning Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Warning", selection: Binding(get: { warningColor }, set: { new in
                        warningColor = new
                        warningHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Overdue Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("Overdue", selection: Binding(get: { overdueColor }, set: { new in
                        overdueColor = new
                        overdueHex = ColorUtils.hexString(from: new)
                    }))
                    .labelsHidden()
                }
            }
        }
        .onAppear {
            // Initialize pickers from stored hex strings
            freshColor = ColorUtils.color(from: freshHex)
            warningColor = ColorUtils.color(from: warningHex)
            overdueColor = ColorUtils.color(from: overdueHex)
        }
    }
}
