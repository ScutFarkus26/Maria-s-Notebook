import SwiftUI
import SwiftData

// MARK: - Roster View UI (Three-Pane Layout, Grid, and List Content)

extension StudentsView {

    // MARK: - Three-Pane Layout Content

    var threePaneSidebar: some View {
        VStack(spacing: 0) {
            // Sort and Filter controls at the top
            if mode == .roster {
                SortFilterControls(
                    sortOrderRaw: $studentsSortOrderRaw,
                    filterRaw: $studentsFilterRaw,
                    effectiveSortOrder: effectiveSortOrder,
                    selectedFilter: selectedFilter,
                    showEditButton: effectiveSortOrder == .manual
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
                Divider()
            }

            // Student list
            NavigationStack {
                rosterListContent
                    .navigationTitle("Students")
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
            .listStyle(.sidebar)
        }
    }

    var threePaneContent: some View {
        NavigationStack {
            if let id = selectedStudentID, let student = uniqueStudents.first(where: { $0.id == id }) {
                StudentDetailView(student: student)
                    .id(student.id)
                    .navigationTitle(student.fullName)
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            } else {
                SelectStudentEmptyState()
            }
        }
    }

    // MARK: - Roster Grid Content

    var rosterGridContent: some View {
        #if os(iOS)
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: nil,
            horizontalSizeClass: horizontalSizeClass
        )
        #else
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: nil
        )
        #endif

        return renderer.gridView
            #if DEBUG
            .onAppear {
                checkForDuplicateIDs(in: filteredStudents)
            }
            .onChange(of: filteredStudents.count) {
                checkForDuplicateIDs(in: filteredStudents)
            }
            .onChange(of: selectedFilter) {
                checkForDuplicateIDs(in: filteredStudents)
            }
            .onChange(of: effectiveSortOrder) {
                checkForDuplicateIDs(in: filteredStudents)
            }
            #endif
    }

    // MARK: - Roster Content (List View)

    var rosterListContent: some View {
        #if os(iOS)
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: $selectedStudentID,
            horizontalSizeClass: horizontalSizeClass
        )
        #else
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: $selectedStudentID
        )
        #endif

        return renderer.listView { source, destination in
            handleManualReorder(from: source, to: destination)
        }
    }

    // MARK: - iPhone Placeholder Views

    #if os(iOS)
    var placeholderContentForMode: some View {
        Group {
            switch mode {
            case .birthday:
                BirthdayModePlaceholderView()
            case .age:
                AgeModePlaceholderView()
            case .lastLesson:
                LastLessonModePlaceholderView()
            default:
                rosterGridContent
            }
        }
    }
    #endif
}
