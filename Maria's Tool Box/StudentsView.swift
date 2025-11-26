import SwiftUI
import SwiftData

/// Top-level view for managing and browsing students.
/// Shows a filter sidebar and a grid of student cards.
struct StudentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var students: [Student]

    @State private var showingAddStudent = false
    @State private var selectedStudent: Student?
    @State private var selectedFilter: StudentsFilter = .all
    @Namespace private var gridNamespace

    // MARK: - Derived data

    /// Students after applying the current filter.
    /// For now this returns all students; the visual filter UI is in place
    /// and can be wired to actual level data later.
    private var filteredStudents: [Student] {
        switch selectedFilter {
        case .all:
            return students
        case .upper:
            return students.filter { $0.level == .upper }
        case .lower:
            return students.filter { $0.level == .lower }
        }
    }

    /// Available level filters.
    private var levelFilters: [StudentsFilter] {
        [.upper, .lower]
    }

    /// Grid layout for the student cards.
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

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
        .sheet(isPresented: Binding(
            get: { selectedStudent != nil },
            set: { isPresented in
                if !isPresented {
                    selectedStudent = nil
                }
            }
        )) {
            if let student = selectedStudent {
                StudentDetailView(student: student) {
                    selectedStudent = nil
                }
            }
        }
    }

    // MARK: - Subviews

    /// Left-hand filter sidebar (All / levels).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Click the plus button to add your first student.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(Array(filteredStudents.enumerated()), id: \.element.id) { index, student in
                            StudentCard(student: student)
                                .matchedGeometryEffect(id: student.id, in: gridNamespace)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                .animation(
                                    .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1).delay(Double(index) * 0.02),
                                    value: filteredStudents
                                )
                                .onTapGesture {
                                    selectedStudent = student
                                }
                        }
                    }
                    .padding(24)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: filteredStudents)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .topTrailing) {
            Button {
                showingAddStudent = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
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
                    .font(.system(size: 13))
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

/// Card UI for a single student in the grid.
private struct StudentCard: View {
    let student: Student

    private var levelColor: Color {
        switch student.level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var levelBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
            Text(student.level.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(levelColor.opacity(0.12))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                levelBadge
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}
