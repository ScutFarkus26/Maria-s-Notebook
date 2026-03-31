// RecordPracticeSheet+StudentChips.swift
// Student selection, date/duration, bottom bar, and save logic.

import OSLog
import SwiftUI
import CoreData

// MARK: - Student Chips Section

extension RecordPracticeSheet {
    var studentChipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Students")
                    .font(AppTheme.ScaledFont.calloutSemibold)

                if !selectedStudentIDs.isEmpty {
                    Text("\(selectedStudentIDs.count) selected")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if chipStudents.isEmpty {
                Text("No students have open practice work for this lesson.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(chipStudents) { student in
                        studentChip(for: student)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("Add student\u{2026}", text: $studentSearchText)
                        .font(AppTheme.ScaledFont.body)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )

                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { student in
                            Button {
                                if let sid = student.id {
                                    manuallyAddedStudentIDs.insert(sid)
                                    selectedStudentIDs.insert(sid)
                                }
                                studentSearchText = ""
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.accentColor)
                                    Text(StudentFormatter.displayName(for: student))
                                        .font(AppTheme.ScaledFont.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
                    )
                }
            }
        }
    }

    func studentChip(for student: Student) -> some View {
        let studentID = student.id ?? UUID()
        let isSelected = selectedStudentIDs.contains(studentID)
        let hasOpenWork = practiceStudentIDs.contains(studentID)

        return Button {
            if isSelected {
                selectedStudentIDs.remove(studentID)
            } else {
                selectedStudentIDs.insert(studentID)
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.captionSemibold)
                if hasOpenWork {
                    Image(systemName: "book.fill")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.light))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date & Duration Section

extension RecordPracticeSheet {
    var dateSection: some View {
        DatePicker("Practice Date", selection: $sessionDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .font(AppTheme.ScaledFont.body)
    }

    var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDuration) {
                Text("Track Duration")
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }

            if hasDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([10, 15, 20, 30], id: \.self) { minutes in
                            Button {
                                durationMinutes = minutes
                            } label: {
                                Text("\(minutes) min")
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                    .foregroundStyle(durationMinutes == minutes ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(
                                                durationMinutes == minutes
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(UIConstants.OpacityConstants.light)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Stepper("Custom: \(durationMinutes) min", value: $durationMinutes, in: 5...120, step: 5)
                        .font(AppTheme.ScaledFont.body)
                }
                .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Bottom Bar & Save

extension RecordPracticeSheet {
    var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                saveSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save Session")
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canSave ? Color.accentColor : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(16)
    }

    @MainActor
    func saveSession() {
        let workItemIDs: [String] = selectedStudentIDs.compactMap { studentID in
            openPracticeWork.first { $0.studentID == studentID.uuidString }?.id?.uuidString
        }

        // Create practice session via Core Data
        let session = CDPracticeSession(context: viewContext)
        session.date = sessionDate
        session.durationInterval = hasDuration ? TimeInterval(durationMinutes * 60) : nil
        session.studentIDsArray = Array(selectedStudentIDs).map(\.uuidString)
        session.workItemIDsArray = workItemIDs
        session.sharedNotes = sessionNotes
        session.location = nil

        session.practiceQualityValue = practiceQuality
        session.independenceLevelValue = independenceLevel

        session.askedForHelp = askedForHelp
        session.helpedPeer = helpedPeer
        session.struggledWithConcept = struggledWithConcept
        session.madeBreakthrough = madeBreakthrough
        session.needsReteaching = needsReteaching
        session.readyForCheckIn = readyForCheckIn
        session.readyForAssessment = readyForAssessment

        if scheduleCheckIn {
            session.checkInScheduledFor = checkInDate
        }
        session.followUpActions = followUpActions
        session.materialsUsed = materialsUsed

        viewContext.safeSave()

        dismiss()
    }
}
