import SwiftUI
import CoreData

// MARK: - Roster View UI (Three-Pane Layout, Grid, and List Content)

extension StudentsView {

    // MARK: - Three-Pane Layout Content

    var threePaneSidebar: some View {
        VStack(spacing: 0) {
            if mode == .roster {
                threePaneSortFilterControls
                Divider()
            }

            NavigationStack {
                rosterListContent
                    .navigationTitle("Students")
                    .inlineNavigationTitle()
            }
            .listStyle(.sidebar)
        }
    }

    private var threePaneSortFilterControls: some View {
        VStack(spacing: 8) {
            SortFilterControls(
                sortOrderRaw: $studentsSortOrderRaw,
                filterRaw: $studentsFilterRaw,
                effectiveSortOrder: effectiveSortOrder,
                selectedFilter: selectedFilter,
                showEditButton: effectiveSortOrder == .manual
            )

            SearchField("Search students", text: $searchText)
                .onSubmit {
                    if let first = filteredStudents.first {
                        selectedStudentID = first.id
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    var threePaneContent: some View {
        NavigationStack {
            if let id = selectedStudentID, let student = uniqueStudents.first(where: { $0.id == id }) {
                StudentDetailView(student: student)
                    .id(student.id)
                    .navigationTitle(student.fullName)
                    .inlineNavigationTitle()
            } else {
                SelectStudentEmptyState()
            }
        }
    }

    // MARK: - Roster Grid Content

    var rosterGridContent: some View {
        #if os(iOS)
        let sizeClass = horizontalSizeClass
        #else
        let sizeClass: UserInterfaceSizeClass? = nil
        #endif

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
            horizontalSizeClass: sizeClass
        )

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
        let sizeClass = horizontalSizeClass
        #else
        let sizeClass: UserInterfaceSizeClass? = nil
        #endif

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
            horizontalSizeClass: sizeClass
        )

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
            default:
                rosterGridContent
            }
        }
    }
    #endif
}
