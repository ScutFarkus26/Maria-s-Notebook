// GapActionSheet.swift
// Shows unscheduled lessons for a subject gap, allowing quick inbox additions.

import SwiftUI
import CoreData

struct GapActionSheet: View {
    let subject: String
    let context: NSManagedObjectContext

    @Environment(\.dismiss) private var dismiss
    @State private var addedLessonIDs: Set<UUID> = []

    @FetchRequest private var lessons: FetchedResults<CDLesson>
    @FetchRequest private var existingAssignments: FetchedResults<CDLessonAssignment>
    @FetchRequest(sortDescriptors: CDStudent.sortByName) private var studentsRaw: FetchedResults<CDStudent>

    private var enrolledStudents: [CDStudent] {
        Array(studentsRaw).uniqueByID.filterEnrolled()
    }

    init(subject: String, context: NSManagedObjectContext) {
        self.subject = subject
        self.context = context

        _lessons = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.sortIndex, ascending: true)],
            predicate: NSPredicate(format: "subject ==[c] %@", subject)
        )
        _existingAssignments = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: false)],
            predicate: NSPredicate(format: "presentedAt == nil")
        )
    }

    /// Lessons that don't already have an unscheduled assignment in the inbox.
    private var availableLessons: [CDLesson] {
        let existingLessonIDs = Set(existingAssignments.compactMap { UUID(uuidString: $0.lessonID) })
        return lessons.filter { lesson in
            guard let id = lesson.id else { return false }
            return !existingLessonIDs.contains(id) && !addedLessonIDs.contains(id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if availableLessons.isEmpty && addedLessonIDs.isEmpty {
                    ContentUnavailableView {
                        Label("All \(subject) Lessons Planned", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every \(subject) lesson is already in your inbox or has been presented.")
                    }
                } else {
                    if !addedLessonIDs.isEmpty {
                        Section {
                            Label(
                                "\(addedLessonIDs.count) lesson\(addedLessonIDs.count == 1 ? "" : "s") added to inbox",
                                systemImage: "tray.fill"
                            )
                            .font(AppTheme.ScaledFont.callout)
                            .foregroundStyle(AppColors.success)
                        }
                    }

                    Section("Available \(subject) Lessons") {
                        ForEach(availableLessons, id: \.objectID) { lesson in
                            lessonRow(lesson)
                        }
                    }
                }
            }
            .navigationTitle("Address \(subject) Gap")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        #if !os(macOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func lessonRow(_ lesson: CDLesson) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.name)
                    .font(AppTheme.ScaledFont.callout)
                if !lesson.group.isEmpty {
                    Text(lesson.group)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                addToInbox(lesson)
            } label: {
                Label("Add to Inbox", systemImage: "tray.and.arrow.down")
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @MainActor
    private func addToInbox(_ lesson: CDLesson) {
        guard let lessonID = lesson.id else { return }
        let studentIDs = enrolledStudents.compactMap(\.id)
        _ = PresentationFactory.makeDraft(
            lessonID: lessonID,
            studentIDs: studentIDs,
            context: context
        )
        _ = context.safeSave()
        addedLessonIDs.insert(lessonID)
    }
}
