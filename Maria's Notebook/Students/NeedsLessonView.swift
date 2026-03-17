import SwiftUI
import SwiftData

/// Standalone view showing which students need a lesson, sorted by urgency.
/// Promoted from the former StudentMode.lastLesson to a top-level Planning nav item.
struct NeedsLessonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter

    @Query private var students: [Student]

    // Change detection for lesson assignments
    @Query(sort: [SortDescriptor(\LessonAssignment.id)])
    private var lessonAssignmentsForChange: [LessonAssignment]

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var daysSinceLastLesson: [UUID: Int] = [:]
    @State private var selectedStudentForSheet: Student?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var visibleStudents: [Student] {
        let visible = TestStudentsFilter.filterVisible(
            students.filter { $0.isEnrolled },
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
        return visible.uniqueByID
    }

    private var sortedStudents: [Student] {
        let daysMap = daysSinceLastLesson
        return visibleStudents.sorted { lhs, rhs in
            let lDays = daysMap[lhs.id] ?? -1
            let rDays = daysMap[rhs.id] ?? -1
            // Students with no presentations (-1) go first
            if lDays == -1 && rDays == -1 {
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
            if lDays == -1 { return true }
            if rDays == -1 { return false }
            if lDays == rDays {
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
            return lDays > rDays // More days = needs lesson more urgently
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                LastLessonModePlaceholderView()
            } else {
                gridContent
            }
            #else
            gridContent
            #endif
        }
        .navigationTitle("Needs Lesson")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { reloadData() }
        .onChange(of: lessonAssignmentsForChange.count) { _, _ in
            reloadData()
        }
        .sheet(item: $selectedStudentForSheet) { student in
            StudentDetailView(student: student)
                .id(student.id)
            #if os(macOS)
                .frame(minWidth: 860, minHeight: 640)
                .presentationSizingFitted()
            #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            #endif
        }
    }

    private var gridContent: some View {
        Group {
            if sortedStudents.isEmpty {
                ContentUnavailableView(
                    "No Students",
                    systemImage: "person.3",
                    description: Text("Add students to see who needs a lesson.")
                )
            } else {
                StudentsCardsGridView(
                    students: sortedStudents,
                    isBirthdayMode: false,
                    isAgeMode: false,
                    isLastLessonMode: true,
                    lastLessonDays: daysSinceLastLesson,
                    isManualMode: false,
                    onTapStudent: { student in
                        selectedStudentForSheet = student
                    },
                    onReorder: { _, _, _, _ in }
                )
            }
        }
    }

    private func reloadData() {
        let viewModel = StudentsViewModel()
        daysSinceLastLesson = viewModel.computeDaysSinceLastLessonCache(
            for: visibleStudents,
            using: modelContext,
            calendar: calendar
        )
    }
}
