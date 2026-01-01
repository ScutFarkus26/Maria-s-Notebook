// StudentChecklistTab.swift
// Checklist tab content extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentChecklistTab: View {
    let student: Student
    let subjects: [String]
    let selectedSubject: String?
    let lessons: [Lesson]
    let studentLessonsRaw: [StudentLesson]
    let rowStatesByLesson: [UUID: StudentChecklistRowState]
    
    let onSubjectSelected: (String?) -> Void
    let onTapScheduled: (Lesson, StudentChecklistRowState?) -> Void
    let onTapPresented: (Lesson, StudentChecklistRowState?) -> Void
    let onTapActive: (Lesson, StudentChecklistRowState?) -> Void
    let onTapComplete: (Lesson, StudentChecklistRowState?) -> Void
    
    private let lessonsVM = LessonsViewModel()
    
    private func makeChecklistSection(for subject: String) -> some View {
        let groups = lessonsVM.groups(for: subject, lessons: lessons)
        return SubjectChecklistSection(
            subject: subject,
            orderedGroups: groups,
            lessons: lessons,
            rowStatesByLesson: rowStatesByLesson,
            onTapScheduled: onTapScheduled,
            onTapPresented: onTapPresented,
            onTapActive: onTapActive,
            onTapComplete: onTapComplete
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubjectPillsView(subjects: subjects, selected: selectedSubject) { subject in
                onSubjectSelected(subject)
            }

            if let subject = selectedSubject ?? subjects.first {
                makeChecklistSection(for: subject)
            } else {
                ContentUnavailableView {
                    Label("No Subjects", systemImage: "text.book.closed")
                } description: {
                    Text("Add lessons in Albums to see subjects here.")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 36)
    }
}

