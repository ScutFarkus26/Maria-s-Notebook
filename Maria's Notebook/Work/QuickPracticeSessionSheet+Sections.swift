// QuickPracticeSessionSheet+Sections.swift
// Partner, behavior, notes, next steps, and bottom bar sections extracted from QuickPracticeSessionSheet

import SwiftUI
import SwiftData
import os

extension QuickPracticeSessionSheet {
    // MARK: - Partner Section

    var partnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                adaptiveWithAnimation {
                    showPartnerSelector.toggle()
                }
            } label: {
                HStack {
                    Text("Practice Partners")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.primary)

                    Text("(Optional)")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !selectedPartnerIDs.isEmpty {
                        Text("\(selectedPartnerIDs.count)")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor))
                    }

                    Image(systemName: showPartnerSelector ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showPartnerSelector {
                if suggestedPartners.isEmpty {
                    Text("No co-learners found")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(suggestedPartners) { partner in
                        partnerRow(for: partner)
                    }
                }
            }
        }
    }

    func partnerRow(for student: Student) -> some View {
        Button {
            if selectedPartnerIDs.contains(student.id) {
                selectedPartnerIDs.remove(student.id)
            } else {
                selectedPartnerIDs.insert(student.id)
            }
        } label: {
            HStack {
                Image(systemName: selectedPartnerIDs.contains(student.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedPartnerIDs.contains(student.id) ? .blue : .secondary)
                    .font(.system(size: 20))

                Text(StudentFormatter.displayName(for: student))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPartnerIDs.contains(student.id) ? Color.blue.opacity(UIConstants.OpacityConstants.light) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behaviors Section

    var behaviorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observable Behaviors")
                .font(AppTheme.ScaledFont.calloutSemibold)

            VStack(spacing: 8) {
                behaviorToggle("Asked for help", isOn: $askedForHelp, icon: "hand.raised.fill", color: .orange)
                behaviorToggle("Helped a peer", isOn: $helpedPeer, icon: "hands.sparkles.fill", color: .green)
                behaviorToggle(
                    "Struggled with concept",
                    isOn: $struggledWithConcept,
                    icon: "exclamationmark.triangle.fill", color: .red
                )
                behaviorToggle(
                    "Made breakthrough",
                    isOn: $madeBreakthrough,
                    icon: "lightbulb.fill", color: .yellow
                )
                behaviorToggle(
                    "Needs reteaching",
                    isOn: $needsReteaching,
                    icon: "arrow.counterclockwise.circle.fill",
                    color: .purple
                )
                behaviorToggle(
                    "Ready for check-in",
                    isOn: $readyForCheckIn,
                    icon: "checkmark.circle.fill", color: .blue
                )
                behaviorToggle(
                    "Ready for assessment",
                    isOn: $readyForAssessment,
                    icon: "checkmark.seal.fill", color: .indigo
                )
            }
        }
    }

    func behaviorToggle(_ label: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn.wrappedValue ? color : .secondary)

                Text(label)
                    .font(AppTheme.ScaledFont.body)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Notes Section

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Notes")
                .font(AppTheme.ScaledFont.calloutSemibold)

            TextEditor(text: $sessionNotes)
                .font(AppTheme.ScaledFont.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: 1)
                )
        }
    }

    // MARK: - Next Steps Section

    var nextStepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Steps")
                .font(AppTheme.ScaledFont.calloutSemibold)
                .foregroundStyle(.primary)

            // Schedule check-in
            Toggle(isOn: $scheduleCheckIn) {
                Text("Schedule Check-in")
                    .font(AppTheme.ScaledFont.body)
            }

            if scheduleCheckIn {
                DatePicker("Check-in Date", selection: $checkInDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(AppTheme.ScaledFont.body)
                    .padding(.leading, 24)
            }

            // Follow-up actions
            VStack(alignment: .leading, spacing: 6) {
                Text("Follow-up Actions")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g., 'Reteach borrowing', 'Create scaffolded worksheet'",
                    text: $followUpActions, axis: .vertical
                )
                    .font(AppTheme.ScaledFont.body)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                    )
                    .lineLimit(2...4)
            }

            // Materials used
            VStack(alignment: .leading, spacing: 6) {
                Text("Materials Used")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                TextField("e.g., 'Manipulatives', 'Worksheet pg 12'", text: $materialsUsed)
                    .font(AppTheme.ScaledFont.body)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
                    )
            }
        }
    }

    // MARK: - Bottom Bar

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
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Save

    @MainActor
    func saveSession() {
        // Build student IDs list
        var studentIDs = [workItem.studentID]
        studentIDs.append(contentsOf: selectedPartnerIDs.map(\.uuidString))

        // Create practice session
        let session = repository.create(
            date: sessionDate,
            duration: hasDuration ? TimeInterval(durationMinutes * 60) : nil,
            studentIDs: studentIDs.map { UUID(uuidString: $0)! },
            workItemIDs: [UUID(uuidString: workItem.id.uuidString)!],
            sharedNotes: sessionNotes,
            location: nil
        )

        // Set quality metrics
        session.practiceQuality = practiceQuality
        session.independenceLevel = independenceLevel

        // Set behavior flags
        session.askedForHelp = askedForHelp
        session.helpedPeer = helpedPeer
        session.struggledWithConcept = struggledWithConcept
        session.madeBreakthrough = madeBreakthrough
        session.needsReteaching = needsReteaching
        session.readyForCheckIn = readyForCheckIn
        session.readyForAssessment = readyForAssessment

        // Set next steps
        if scheduleCheckIn {
            session.checkInScheduledFor = checkInDate
        }
        session.followUpActions = followUpActions
        session.materialsUsed = materialsUsed

        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save quick practice session: \(error)")
        }

        onSave?(session)
        dismiss()
    }
}
