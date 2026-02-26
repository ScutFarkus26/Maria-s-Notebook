// GroupProgressionView.swift
// Matrix view showing all students' progress through a subject/group.

import SwiftUI
import SwiftData

/// Shows a student × lesson matrix for a single subject/group.
struct GroupProgressionView: View {
    let subject: String
    let group: String

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GroupProgressionViewModel()
    @State private var isShowingStudentPicker = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.students.isEmpty {
                ContentUnavailableView {
                    Label("No Students", systemImage: "person.3")
                } description: {
                    Text("No students have activity in \(subject) > \(group) yet.")
                }
            } else if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .navigationTitle("\(subject) > \(group)")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingStudentPicker = true
                } label: {
                    Image(systemName: SFSymbol.Action.plus)
                }
                .accessibilityLabel("Add students")
            }
        }
        .sheet(isPresented: $isShowingStudentPicker) {
            studentPickerSheet
        }
        .navigationDestination(for: StudentProgressionRoute.self) { route in
            if let student = viewModel.students.first(where: { $0.id == route.studentID }) {
                StudentSubjectProgressionView(student: student, subject: route.subject, group: route.group)
            }
        }
        .onAppear {
            viewModel.configure(subject: subject, group: group, context: modelContext)
        }
        .overlay(alignment: .bottom) {
            if !viewModel.selectedStudentIDs.isEmpty {
                ProgressionBatchActionBar(
                    selectedCount: viewModel.selectedStudentIDs.count,
                    onScheduleNext: {
                        viewModel.scheduleNextLesson(context: modelContext)
                        viewModel.configure(subject: subject, group: group, context: modelContext)
                    },
                    onDeselectAll: {
                        viewModel.selectedStudentIDs.removeAll()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: viewModel.selectedStudentIDs.isEmpty)
            }
        }
    }

    // MARK: - Regular Layout (iPad/Mac)

    private var regularLayout: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    Text("Student")
                        .font(.caption.bold())
                        .frame(width: 160, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.bar)

                    ForEach(viewModel.lessons) { lesson in
                        Text(lesson.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .frame(width: 80)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                // Student rows grouped by cluster
                if !viewModel.needsAttention.isEmpty {
                    clusterSection("Needs Attention", students: viewModel.needsAttention, tint: .orange)
                }
                if !viewModel.practicing.isEmpty {
                    clusterSection("Practicing", students: viewModel.practicing, tint: .blue)
                }
                if !viewModel.readyForNext.isEmpty {
                    clusterSection("Ready for Next", students: viewModel.readyForNext, tint: .green)
                }
                if !viewModel.unclustered.isEmpty {
                    clusterSection("Other", students: viewModel.unclustered, tint: .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func clusterSection(_ title: String, students: [Student], tint: Color) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .gridCellColumns(1 + viewModel.lessons.count)
        }

        ForEach(students) { student in
            studentMatrixRow(student)
        }
    }

    private func studentMatrixRow(_ student: Student) -> some View {
        GridRow {
            HStack(spacing: 6) {
                Toggle(isOn: Binding(
                    get: { viewModel.selectedStudentIDs.contains(student.id) },
                    set: { isOn in
                        if isOn { viewModel.selectedStudentIDs.insert(student.id) }
                        else { viewModel.selectedStudentIDs.remove(student.id) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                NavigationLink(value: StudentProgressionRoute(studentID: student.id, subject: subject, group: group)) {
                    Text(student.fullName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ForEach(viewModel.lessons) { lesson in
                let status = viewModel.matrix[student.id]?[lesson.id] ?? .notStarted
                ProgressionMatrixCell(
                    status: status,
                    lessonName: lesson.name,
                    studentName: student.fullName
                )
                .frame(width: 80)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        List {
            if !viewModel.needsAttention.isEmpty {
                compactSection("Needs Attention", students: viewModel.needsAttention, tint: .orange)
            }
            if !viewModel.practicing.isEmpty {
                compactSection("Practicing", students: viewModel.practicing, tint: .blue)
            }
            if !viewModel.readyForNext.isEmpty {
                compactSection("Ready for Next", students: viewModel.readyForNext, tint: .green)
            }
            if !viewModel.unclustered.isEmpty {
                compactSection("Other", students: viewModel.unclustered, tint: .secondary)
            }
        }
    }

    @ViewBuilder
    private func compactSection(_ title: String, students: [Student], tint: Color) -> some View {
        Section {
            ForEach(students) { student in
                NavigationLink(value: StudentProgressionRoute(studentID: student.id, subject: subject, group: group)) {
                    compactStudentRow(student)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
            }
        }
    }

    private func compactStudentRow(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(student.fullName)
                .font(.body)

            // Dot strip
            HStack(spacing: 3) {
                ForEach(viewModel.lessons) { lesson in
                    let status = viewModel.matrix[student.id]?[lesson.id] ?? .notStarted
                    Circle()
                        .fill(status.color.opacity(status == .notStarted ? 0.3 : 1.0))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Student Picker

    private var studentPickerSheet: some View {
        NavigationStack {
            let available = viewModel.availableStudents()
            List {
                if available.isEmpty {
                    Text("All students are already in this group view.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available) { student in
                        Button {
                            viewModel.addStudent(student)
                            isShowingStudentPicker = false
                        } label: {
                            Text(student.fullName)
                        }
                    }
                }
            }
            .navigationTitle("Add Student")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingStudentPicker = false
                    }
                }
            }
        }
    }
}
