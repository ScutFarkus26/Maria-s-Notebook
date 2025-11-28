import SwiftUI
import SwiftData

/// Top-level view for managing and browsing students.
/// Shows a filter sidebar and a grid of student cards.
struct StudentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]

    @State private var sortOrder: SortOrder = .alphabetical

    @State private var showingAddStudent = false
    @State private var selectedStudent: Student?
    @State private var selectedFilter: StudentsFilter = .all

    /// Returns students ordered by the persisted manual order, with any missing/extra appended.
    private func applyManualOrder(to students: [Student]) -> [Student] {
        return students.sorted { (lhs: Student, rhs: Student) -> Bool in
            lhs.manualOrder < rhs.manualOrder
        }
    }

    /// Assigns sequential manualOrder values based on the provided ordered IDs.
    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = students.first(where: { $0.id == id }) {
                s.manualOrder = idx
            }
        }
    }

    /// If no manual order has been assigned yet, seed it alphabetically.
    private func ensureInitialManualOrderIfNeeded() {
        let all = students
        guard !all.isEmpty else { return }
        let allZero = all.allSatisfy { $0.manualOrder == 0 }
        if allZero {
            let sorted = all.sorted { (lhs: Student, rhs: Student) -> Bool in
                lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
            for (idx, s) in sorted.enumerated() {
                s.manualOrder = idx
            }
            try? modelContext.save()
        }
    }

    /// Students after applying the current filter and sort order.
    private var filteredStudents: [Student] {
        let base: [Student]
        switch selectedFilter {
        case .all:
            base = students
        case .upper:
            base = students.filter { $0.level == .upper }
        case .lower:
            base = students.filter { $0.level == .lower }
        }

        switch sortOrder {
        case .alphabetical:
            return base.sorted(by: { (lhs: Student, rhs: Student) -> Bool in
                let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                if nameOrder == .orderedSame { return lhs.manualOrder < rhs.manualOrder }
                return nameOrder == .orderedAscending
            })
        case .age:
            // Sort by birthday (younger first): later birthday comes first
            return base.sorted(by: { (lhs: Student, rhs: Student) -> Bool in
                if lhs.birthday == rhs.birthday { return lhs.manualOrder < rhs.manualOrder }
                return lhs.birthday > rhs.birthday
            })
        case .manual:
            return applyManualOrder(to: base)
        }
    }

    /// Available level filters.
    private var levelFilters: [StudentsFilter] {
        [.upper, .lower]
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            content
        }
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
        }
        .sheet(item: $selectedStudent) { student in
            StudentDetailView(student: student) {
                selectedStudent = nil
            }
        }
        .onAppear {
            ensureInitialManualOrderIfNeeded()
        }
        .onChange(of: students.map { $0.id }) { _ in
            // Seed initial order alphabetically if everything is zero
            ensureInitialManualOrderIfNeeded()

            // Ensure manualOrder values remain unique; assign new students to the end
            let all = students
            guard !all.isEmpty else { return }
            var seen = Set<Int>()
            var duplicates: [Student] = []
            // Keep first occurrence of each order and collect duplicates (e.g., newly added with default 0)
            for s in all.sorted(by: { $0.manualOrder < $1.manualOrder }) {
                if seen.contains(s.manualOrder) {
                    duplicates.append(s)
                } else {
                    seen.insert(s.manualOrder)
                }
            }
            if !duplicates.isEmpty {
                var maxOrder = seen.max() ?? -1
                for s in duplicates {
                    maxOrder += 1
                    s.manualOrder = maxOrder
                }
                try? modelContext.save()
            }
        }
    }

    // MARK: - Subviews

    /// Left-hand filter sidebar (All / levels).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort Order")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            FilterButton(
                icon: "textformat.abc",
                title: "A–Z",
                color: .accentColor,
                isSelected: sortOrder == .alphabetical
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sortOrder = .alphabetical
                }
            }

            FilterButton(
                icon: "calendar",
                title: "Age",
                color: .accentColor,
                isSelected: sortOrder == .age
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sortOrder = .age
                }
            }

            FilterButton(
                icon: "arrow.up.arrow.down",
                title: "Manual",
                color: .accentColor,
                isSelected: sortOrder == .manual
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    sortOrder = .manual
                }
            }
            .padding(.bottom, 8)

            Text("Filters")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // All filter
            FilterButton(
                icon: "person.3.fill",
                title: "All",
                color: .accentColor,
                isSelected: selectedFilter == .all
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    selectedFilter = .all
                }
            }

            // Individual level filters (Upper, Lower, etc.) based on actual data
            ForEach(levelFilters, id: \.self) { filter in
                FilterButton(
                    icon: "circle.fill",
                    title: filter.title,
                    color: filter.color,
                    isSelected: selectedFilter == filter
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        selectedFilter = filter
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 180, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }

    /// Main grid of student cards.
    private var content: some View {
        Group {
            if filteredStudents.isEmpty {
                VStack(spacing: 8) {
                    Text("No students yet")
                        .font(.system(size: AppTheme.FontSize.titleMedium, weight: .semibold, design: .rounded))
                    Text("Click the plus button to add your first student.")
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudentsCardsGridView(
                    students: filteredStudents,
                    isManualMode: sortOrder == .manual,
                    onTapStudent: { selectedStudent = $0 },
                    onReorder: { movingStudent, fromIndex, toIndex, subset in
                        // Reuse existing merge logic from StudentsView
                        let newAllIDs = mergeReorderedSubsetIntoAll(
                            movingID: movingStudent.id,
                            from: fromIndex,
                            to: toIndex,
                            current: subset
                        )
                        assignManualOrder(from: newAllIDs)
                        try? modelContext.save()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .topTrailing) {
            Button {
                showingAddStudent = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: AppTheme.FontSize.titleXLarge))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    /// Merge a reordered filtered subset back into the full ordered list and return the new full ID order.
    private func mergeReorderedSubsetIntoAll(movingID: UUID, from fromIndex: Int, to toIndex: Int, current: [Student]) -> [UUID] {
        // Full list ordered by current manualOrder
        let allOrdered = students.sorted { $0.manualOrder < $1.manualOrder }

        // IDs of the currently visible (filtered) subset
        let subsetIDs = current.map { $0.id }
        var subset = subsetIDs
        // Reorder within the subset
        if let sFrom = subset.firstIndex(of: movingID) {
            let item = subset.remove(at: sFrom)
            let boundedIndex = max(0, min(subset.count, toIndex))
            subset.insert(item, at: boundedIndex)
        }

        // Merge: replace the positions of subset items in the full list with the new subset order
        let subsetSet = Set(subsetIDs)
        var subsetQueue = subset
        var newAllIDs: [UUID] = []
        for s in allOrdered {
            if subsetSet.contains(s.id) {
                // Take next from the reordered subset
                if !subsetQueue.isEmpty {
                    newAllIDs.append(subsetQueue.removeFirst())
                }
            } else {
                newAllIDs.append(s.id)
            }
        }
        return newAllIDs
    }
}

/// Sort options for the students list.
private enum SortOrder: Hashable {
    case manual
    case alphabetical
    case age
}

// MARK: - Filter support types

/// Logical filter for the students list.
private enum StudentsFilter: Hashable {
    case all
    case upper
    case lower

    var title: String {
        switch self {
        case .all:
            return "All"
        case .upper:
            return "Upper"
        case .lower:
            return "Lower"
        }
    }

    var color: Color {
        switch self {
        case .all:
            return .accentColor
        case .upper:
            return Color.pink
        case .lower:
            return Color.blue
        }
    }
}

/// Reusable row used in the filter sidebar.
private struct FilterButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(height: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

