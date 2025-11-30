import SwiftUI
import SwiftData

struct DuplicateStudentsPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onComplete: (StudentDuplicatesCleaner.Summary) -> Void

    @State private var groups: [StudentDuplicatesCleaner.DuplicateGroup] = []
    @State private var selectedPrimary: [String: UUID] = [:] // nameKey -> primaryID
    @State private var selectedDuplicates: [String: Set<UUID>] = [:] // nameKey -> duplicate IDs to merge
    @State private var loadingError: String? = nil

    private var totalGroups: Int { groups.count }
    private var totalSelectedDuplicates: Int {
        groups.reduce(0) { partial, g in
            partial + (selectedDuplicates[g.nameKey]?.count ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.top, 8)

            if let err = loadingError {
                VStack(spacing: 8) {
                    Text("Failed to load duplicates")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                VStack(spacing: 8) {
                    Text("No duplicates found")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Your student list looks clean.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        ForEach(groups, id: \.nameKey) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }

            Divider()
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .frame(minWidth: 680, minHeight: 540)
        .onAppear(perform: loadDuplicates)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Merge Duplicate Students")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                stat("Groups of Students", value: "\(totalGroups)")
                stat("Selected to Merge", value: "\(totalSelectedDuplicates)")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupSection(_ group: StudentDuplicatesCleaner.DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName(for: group))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(group.members.count) records")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(group.members, id: \.id) { member in
                    memberRow(group: group, member: member)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                }
            }
        }
    }

    private func memberRow(group: StudentDuplicatesCleaner.DuplicateGroup, member: Student) -> some View {
        let isPrimary = selectedPrimary[group.nameKey] == member.id
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Primary selector (radio)
            Button(action: {
                setPrimary(member.id, for: group)
            }) {
                Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isPrimary ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help("Set as primary")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(member.firstName) \(member.lastName)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    badge(text: member.level.rawValue)
                    badge(text: "DOB: \(dateOnly(member.birthday))", color: .secondary)
                    if let ds = member.dateStarted { badge(text: "Start: \(dateOnly(ds))", color: .secondary) }
                }
            }

            Spacer()

            if isPrimary {
                Text("Keep")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            } else {
                Toggle(isOn: Binding<Bool>(
                    get: { selectedDuplicates[group.nameKey]?.contains(member.id) ?? false },
                    set: { newValue in
                        if newValue { addDuplicate(member.id, for: group) } else { removeDuplicate(member.id, for: group) }
                    }
                )) {
                    Text("Merge")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .toggleStyle(.switch)
                .frame(width: 120)
            }
        }
    }

    private func badge<S: ShapeStyle>(text: String, color: S = .tint) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private var bottomBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            Button("Merge (\(totalSelectedDuplicates))") { performMerge() }
                .buttonStyle(.borderedProminent)
                .disabled(totalSelectedDuplicates == 0)
        }
    }

    private func loadDuplicates() {
        do {
            let found = try StudentDuplicatesCleaner.findDuplicateGroups(using: modelContext)
            self.groups = found
            // Initialize selections
            var primaries: [String: UUID] = [:]
            var dups: [String: Set<UUID>] = [:]
            for g in found {
                if let primary = StudentDuplicatesCleaner.defaultPrimary(for: g.members) {
                    primaries[g.nameKey] = primary.id
                    let dupIDs = Set(g.members.map { $0.id }.filter { $0 != primary.id })
                    dups[g.nameKey] = dupIDs
                }
            }
            self.selectedPrimary = primaries
            self.selectedDuplicates = dups
        } catch {
            self.loadingError = error.localizedDescription
        }
    }

    private func setPrimary(_ id: UUID, for group: StudentDuplicatesCleaner.DuplicateGroup) {
        selectedPrimary[group.nameKey] = id
        // Remove from duplicates set
        var set = selectedDuplicates[group.nameKey] ?? []
        set.remove(id)
        selectedDuplicates[group.nameKey] = set
    }

    private func addDuplicate(_ id: UUID, for group: StudentDuplicatesCleaner.DuplicateGroup) {
        var set = selectedDuplicates[group.nameKey] ?? []
        if id != selectedPrimary[group.nameKey] { set.insert(id) }
        selectedDuplicates[group.nameKey] = set
    }

    private func removeDuplicate(_ id: UUID, for group: StudentDuplicatesCleaner.DuplicateGroup) {
        var set = selectedDuplicates[group.nameKey] ?? []
        set.remove(id)
        selectedDuplicates[group.nameKey] = set
    }

    private func performMerge() {
        var plans: [StudentDuplicatesCleaner.MergePlan] = []
        for g in groups {
            guard let primary = selectedPrimary[g.nameKey] else { continue }
            let dupIDs = Array(selectedDuplicates[g.nameKey] ?? [])
            if !dupIDs.isEmpty {
                plans.append(.init(primaryID: primary, duplicateIDs: dupIDs))
            }
        }
        guard !plans.isEmpty else { dismiss(); return }
        do {
            let summary = try StudentDuplicatesCleaner.merge(plans: plans, using: modelContext)
            onComplete(summary)
            dismiss()
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func displayName(for group: StudentDuplicatesCleaner.DuplicateGroup) -> String {
        // Prefer the first member's full name for display
        if let first = group.members.first { return "\(first.firstName) \(first.lastName)" }
        return group.nameKey
    }

    private func dateOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

#Preview {
    Text("DuplicateStudentsPreviewView requires app data model for preview.")
}
