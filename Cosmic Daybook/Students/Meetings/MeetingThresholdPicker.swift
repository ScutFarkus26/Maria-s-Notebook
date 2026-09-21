import SwiftUI

// MARK: - Meeting Threshold Picker

struct MeetingThresholdPicker: View {
    @Binding var days: Int
    @Binding var showCompleted: Bool
    @State private var isExpanded = false

    private let presets = [3, 5, 7, 14, 21, 30]

    var body: some View {
        VStack(spacing: 8) {
            // Top row: threshold pill + show completed toggle
            HStack(spacing: 8) {
                // Tappable pill showing current value
                Button {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)

                        Text("Last \(days)d")
                            .font(.subheadline.weight(.medium))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                    )
                    .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)

                // Show completed toggle
                Button {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption)

                        Text("Done")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                showCompleted
                                    ? Color.green.opacity(UIConstants.OpacityConstants.accent)
                                    : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                            )
                    )
                    .foregroundStyle(showCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded picker
            if isExpanded {
                VStack(spacing: 8) {
                    // Quick presets
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                                    days = preset
                                }
                            } label: {
                                Text("\(preset)")
                                    .font(.caption.weight(days == preset ? .semibold : .regular))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(
                                                days == preset
                                                    ? Color.accentColor
                                                    : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
                                            )
                                    )
                                    .foregroundStyle(days == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Fine-tune stepper
                    HStack(spacing: 12) {
                        Button {
                            if days > 1 { days -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(days <= 1)

                        Text("\(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60)

                        Button {
                            if days < 90 { days += 1 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(days >= 90)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}
