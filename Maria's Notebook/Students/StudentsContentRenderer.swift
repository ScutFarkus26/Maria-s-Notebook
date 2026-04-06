import SwiftUI
import CoreData

/// Helper for rendering student content (list/grid) with consistent empty state handling
@MainActor
struct StudentsContentRenderer {
    let students: [CDStudent]
    let effectiveSortOrder: SortOrder
    let daysSinceLastLesson: [UUID: Int]
    let isParsing: Binding<Bool>
    let parsingTask: Binding<Task<Void, Never>?>
    let onAddStudent: () -> Void
    let onTapStudent: ((CDStudent) -> Void)?
    let selectedStudentID: Binding<UUID?>?

    /// nil on macOS; on iOS, determines whether taps open a sheet (compact) or update the detail pane (regular).
    let horizontalSizeClass: UserInterfaceSizeClass?

    /// Render content with empty state check
    @ViewBuilder
    func content<Content: View>(@ViewBuilder contentBuilder: () -> Content) -> some View {
        Group {
            if students.isEmpty {
                NoStudentsEmptyState(onAddStudent: onAddStudent)
            } else {
                contentBuilder()
            }
        }
        .overlay {
            ParsingOverlay(isParsing: isParsing) {
                parsingTask.wrappedValue?.cancel()
            }
        }
    }

    /// Render as grid view
    var gridView: some View {
        content {
            StudentsCardsGridView(
                students: students,
                isBirthdayMode: effectiveSortOrder == .birthday,
                isAgeMode: effectiveSortOrder == .age,
                isLastLessonMode: false,
                lastLessonDays: [:],
                isManualMode: false,
                onTapStudent: onTapStudent ?? { _ in },
                onReorder: { _, _, _, _ in
                    // Reordering not supported in grid view modes
                }
            )
        }
    }

    /// Render as list view
    @ViewBuilder
    func listView(onMove: @escaping (IndexSet, Int) -> Void) -> some View {
        content {
            List(selection: selectedStudentID) {
                ForEach(students, id: \.objectID) { student in
                    StudentListRow(
                        student: student,
                        sortOrder: effectiveSortOrder,
                        daysSinceLastLesson: student.id.flatMap { daysSinceLastLesson[$0] }
                    )
                    .tag(student.id)
                    .onTapGesture {
                        handleTap(student)
                    }
                }
                .onMove(perform: onMove)
            }
        }
    }

    /// Routes taps by platform: compact (iPhone) opens a sheet via onTapStudent;
    /// regular/nil (iPad, macOS) updates the selectedStudentID binding for the detail pane.
    private func handleTap(_ student: CDStudent) {
        if horizontalSizeClass == .compact, let onTap = onTapStudent {
            onTap(student)
        } else if let binding = selectedStudentID {
            binding.wrappedValue = student.id
        }
    }
}
