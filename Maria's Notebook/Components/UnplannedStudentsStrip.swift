import SwiftUI
import SwiftData

struct UnplannedStudentsStrip: View {
    let date: Date
    let unplanned: [Student]
    let onSelect: (Student) -> Void

    @State private var expanded: Bool = false

    init(date: Date, unplanned: [Student], onSelect: @escaping (Student) -> Void) {
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
        return Set(counts.filter { $0.value > 1 }.map { $0.key })
    }

    private func chipLabel(for student: Student) -> String {
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }

            if expanded {
                Divider()
                    .overlay(Color.primary.opacity(0.06))
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
                                        Capsule().fill(Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1)
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
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    let s1 = Student(firstName: "Ava", lastName: "Ng", birthday: Date(), level: .lower)
    let s2 = Student(firstName: "Liam", lastName: "C.", birthday: Date(), level: .upper)
    let s3 = Student(firstName: "Ava", lastName: "Smith", birthday: Date(), level: .upper)
    let s4 = Student(firstName: "Noah", lastName: "Brown", birthday: Date(), level: .lower)

    return VStack(alignment: .leading, spacing: 12) {
        UnplannedStudentsStrip(date: Date(), unplanned: [s1, s2, s3, s4]) { _ in }
            .padding()
        UnplannedStudentsStrip(date: Date(), unplanned: []) { _ in }
            .padding()
    }
}
