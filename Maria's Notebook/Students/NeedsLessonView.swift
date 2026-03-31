import SwiftUI
import CoreData

/// Standalone view showing which students need a lesson, sorted by urgency.
/// Promoted from the former StudentMode.lastLesson to a top-level Planning nav item.
struct NeedsLessonView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    @Environment(\.appRouter) private var appRouter

    @FetchRequest(sortDescriptors: []) private var students: FetchedResults<CDStudent>

    // Change detection for lesson assignments
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.id, ascending: true)])
    private var lessonAssignmentsForChange: FetchedResults<CDLessonAssignment>

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    // swiftlint:disable:next line_length
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @State private var daysSinceLastLesson: [UUID: Int] = [:]
    @State private var selectedStudentForSheet: CDStudent?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var visibleStudents: [CDStudent] {
        let visible = TestStudentsFilter.filterVisible(
            students.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
        return visible.uniqueByID
    }

    private var sortedStudents: [CDStudent] {
        let daysMap = daysSinceLastLesson
        return visibleStudents.sorted { lhs, rhs in
            let lDays = lhs.id.flatMap { daysMap[$0] } ?? -1
            let rDays = rhs.id.flatMap { daysMap[$0] } ?? -1
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
        .inlineNavigationTitle()
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
            using: viewContext,
            calendar: calendar
        )
    }
}
