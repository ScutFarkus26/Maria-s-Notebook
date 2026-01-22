// StudentInspectorView.swift
// Lightweight preview for macOS inspector pane showing key student info.

import SwiftUI
import SwiftData

#if os(macOS)
/// A lightweight preview view for the macOS inspector pane.
/// Shows essential student information without the full detail view complexity.
@available(macOS 14.0, *)
struct StudentInspectorView: View {
    let student: Student
    var onOpenFullDetails: (() -> Void)?
    var onOpenInNewWindow: (() -> Void)?

    @Environment(\.calendar) private var calendar

    private var ageDisplay: String {
        let components = AgeUtils.quarterRoundedAgeComponents(birthday: student.birthday)
        let y = components.years
        let m = components.months
        switch m {
        case 0: return "\(y) years old"
        case 3: return "\(y) 1/4 years old"
        case 6: return "\(y) 1/2 years old"
        case 9: return "\(y) 3/4 years old"
        default: return "\(y) years old"
        }
    }

    private var birthdayDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: student.birthday)
    }

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with avatar
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [levelColor.opacity(0.8), levelColor]),
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: 32
                                )
                            )
                            .frame(width: 56, height: 56)

                        Text(student.initials)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(student.fullName)
                            .font(.title3.weight(.semibold))

                        Text(student.level.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Quick Info
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Age", value: ageDisplay)
                    InfoRow(label: "Birthday", value: birthdayDisplay)
                }

                Divider()

                // Actions
                VStack(spacing: 8) {
                    if let onOpenFullDetails {
                        Button {
                            onOpenFullDetails()
                        } label: {
                            Label("View Full Details", systemImage: "person.text.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let onOpenInNewWindow {
                        Button {
                            onOpenInNewWindow()
                        } label: {
                            Label("Open in New Window", systemImage: "uiwindow.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
    }
}

@available(macOS 14.0, *)
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
        }
    }
}
#endif

// Extension to get initials from Student
extension Student {
    var initials: String {
        let parts = fullName.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let last = parts.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        } else if let first = fullName.first {
            return String(first).uppercased()
        } else {
            return "?"
        }
    }
}
