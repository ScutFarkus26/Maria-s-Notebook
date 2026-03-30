// RecordPracticeSheet+Sections.swift
// Quality metrics, behaviors, notes, and next steps sections.

import SwiftUI

// MARK: - Quality Metrics Section

extension RecordPracticeSheet {
    var qualityMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality Metrics")
                .font(AppTheme.ScaledFont.calloutSemibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Practice Quality")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: practiceQuality, color: .blue) {
                            practiceQuality = level
                        }
                    }
                    Spacer()
                    if let quality = practiceQuality {
                        Text(qualityLabel(for: quality))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Independence Level")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        qualityCircle(level: level, selected: independenceLevel, color: .green) {
                            independenceLevel = level
                        }
                    }
                    Spacer()
                    if let independence = independenceLevel {
                        Text(independenceLabel(for: independence))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func qualityCircle(level: Int, selected: Int?, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.opacity((selected ?? 0) >= level ? 1.0 : 0.2))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    func qualityLabel(for level: Int) -> String {
        switch level {
        case 1: return "Distracted"
        case 2: return "Minimal"
        case 3: return "Adequate"
        case 4: return "Good"
        case 5: return "Excellent"
        default: return ""
        }
    }

    func independenceLabel(for level: Int) -> String {
        switch level {
        case 1: return "Constant Help"
        case 2: return "Frequent Guidance"
        case 3: return "Some Support"
        case 4: return "Mostly Independent"
        case 5: return "Fully Independent"
        default: return ""
        }
    }
}

// MARK: - Behaviors Section

extension RecordPracticeSheet {
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
}

// MARK: - Notes Section

extension RecordPracticeSheet {
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
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: 1)
                )
        }
    }
}

// MARK: - Next Steps Section

extension RecordPracticeSheet {
    var nextStepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Steps")
                .font(AppTheme.ScaledFont.calloutSemibold)

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
                        .fill(Color.primary.opacity(0.05))
                )
                .lineLimit(2...4)
            }

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
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
    }
}
