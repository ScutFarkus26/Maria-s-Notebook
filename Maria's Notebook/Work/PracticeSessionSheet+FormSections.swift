import SwiftUI
import SwiftData

// MARK: - Form Sections

extension PracticeSessionSheet {

    var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Practice Date")

            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }

    var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PracticeSectionHeader(title: "Session Quality")

            RatingLevelSelector(
                label: "Engagement Level",
                selectedLevel: $practiceQuality,
                color: .blue,
                levelLabels: PracticeSessionLabels.qualityLabel
            )

            RatingLevelSelector(
                label: "Independence Level",
                selectedLevel: $independenceLevel,
                color: .green,
                levelLabels: PracticeSessionLabels.independenceLabel
            )
        }
    }

    var optionalFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionalFieldToggle(title: "Track Duration", isEnabled: $hasDuration) {
                HStack {
                    Text("Duration (minutes)")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .onChange(of: durationMinutes) { _, newValue in
                    duration = TimeInterval(newValue * 60)
                }
            }
            .onChange(of: hasDuration) { _, newValue in
                if !newValue {
                    duration = nil
                }
            }

            OptionalFieldToggle(title: "Add Location", isEnabled: $hasLocation) {
                TextField("Location (e.g., Small table, Outside)", text: $location)
                    .font(AppTheme.ScaledFont.body)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
            .onChange(of: hasLocation) { _, newValue in
                if !newValue {
                    location = ""
                }
            }
        }
    }

    var individualNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeader(title: "Individual Student Notes")

            ForEach(selectedStudents) { student in
                individualStudentCard(for: student)
            }
        }
    }

    @ViewBuilder
    func individualStudentCard(for student: Student) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(StudentFormatter.displayName(for: student))
                .font(AppTheme.ScaledFont.bodySemibold)

            StudentUnderstandingSelector(level: Binding(
                get: { individualUnderstandingLevels[student.id] ?? 3 },
                set: { individualUnderstandingLevels[student.id] = $0 }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                StyledNotesTextField(
                    placeholder: "Add notes for \(StudentFormatter.displayName(for: student))...",
                    text: Binding(
                        get: { individualNotes[student.id] ?? "" },
                        set: { individualNotes[student.id] = $0 }
                    )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
