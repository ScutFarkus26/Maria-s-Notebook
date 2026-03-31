import SwiftUI
import CoreData

struct UnplannedStudentsStrip: View {
    let date: Date
    let unplanned: [CDStudent]
    let onSelect: (CDStudent) -> Void

    @State private var expanded: Bool = false

    init(date: Date, unplanned: [CDStudent], onSelect: @escaping (CDStudent) -> Void) {
        self.date = date
        self.unplanned = unplanned
        self.onSelect = onSelect
    }

    // Compute duplicate first names (case-insensitive, trimmed)
    private var duplicateFirstNames: Set<String> {
        var counts: [String: Int] = [:]
        for s in unplanned {
            let key = s.firstName.normalizedForComparison()
            counts[key, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.map(\.key))
    }

    private func chipLabel(for student: CDStudent) -> String {
        let first = student.firstName.trimmed()
        let key = first.lowercased()
        if duplicateFirstNames.contains(key) {
            if let initial = student.lastName.trimmed().first {
                return first + " " + String(initial).uppercased() + "."
            }
        }
        return first
    }

    @ViewBuilder
    var body: some View {
        if unplanned.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .foregroundStyle(.secondary)
                Text("Unplanned today · \(unplanned.count)")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            }

            if expanded {
                Divider()
                    .overlay(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(unplanned, id: \.id) { student in
                            Button {
                                onSelect(student)
                            } label: {
                                Text(chipLabel(for: student))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.primary.opacity(UIConstants.OpacityConstants.accent), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
                )
        )
    }
}

#Preview {
    UnplannedStudentsStrip(date: Date(), unplanned: []) { _ in }
        .padding()
        .previewEnvironment()
}
