// StudentProgressTabViewModel.swift
// ViewModel for StudentProgressTab - handles data loading and business logic

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class StudentProgressTabViewModel {
    // MARK: - Public State
    /// The sequences the child is in the middle of: at least one lesson given,
    /// not every lesson mastered. Read from her presentation rows and the
    /// sequences' lessons (`SequenceStanding`), never from stored rows.
    private(set) var standings: [SequenceStanding] = []
    private(set) var activeProjects: [CDProject] = []
    private(set) var activeReports: [CDWorkModel] = []
    /// Per-sequence activity, precomputed once in loadData so the view
    /// doesn't recompute it for every card on every render.
    private(set) var statsByStanding: [String: SequenceStats] = [:]

    // MARK: - Private State
    private var studentID: UUID?
    private var context: NSManagedObjectContext?
    /// Lessons looked up by id on demand (`nil` remembers a miss). The tab
    /// only ever needs the lesson behind an untitled report, so the lesson
    /// table is never loaded whole.
    private var lessonsByID: [UUID: CDLesson?] = [:]
    /// This student's work rows.
    private var allWorkModels: [CDWorkModel] = []

    // MARK: - Initialization

    func configure(for student: CDStudent, context: NSManagedObjectContext) {
        self.studentID = student.id
        loadData(for: student, context: context)
    }

    // MARK: - Data Loading

    /// Every fetch is scoped to the student or to one sequence's lessons, so
    /// the classmates' rows stop being materialised.
    func loadData(for student: CDStudent, context: NSManagedObjectContext) {
        self.context = context
        lessonsByID = [:]
        let studentIDString = student.id?.uuidString ?? ""

        standings = SequenceStandingLoader.standings(forStudentID: studentIDString, in: context)
            .filter(\.isInProgress)

        let workDescriptor = CDFetchRequest(CDWorkModel.self)
        workDescriptor.predicate = NSPredicate(format: "studentID == %@", studentIDString)
        workDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        allWorkModels = context.safeFetch(workDescriptor)

        let projectDescriptor = CDFetchRequest(CDProject.self)
        projectDescriptor.predicate = NSPredicate(format: "isActive == YES")
        projectDescriptor.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let allProjects = context.safeFetch(projectDescriptor)

        activeProjects = allProjects.filter { $0.memberStudentIDsArray.contains(studentIDString) && $0.isActive }
        activeReports = allWorkModels.filter {
            $0.studentID == studentIDString && $0.kind == .report && $0.status.isOpen
        }

        var computed: [String: SequenceStats] = [:]
        for standing in standings {
            computed[standing.id] = sequenceStats(for: standing, studentIDString: studentIDString, context: context)
        }
        statsByStanding = computed
    }

    /// The lesson with this id, fetched once per load. Matches what the
    /// name-sorted whole-table scan returned: the first by name when a
    /// duplicate exists.
    private func lesson(for lessonID: UUID) -> CDLesson? {
        if let cached = lessonsByID[lessonID] { return cached }
        guard let context else { return nil }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 1
        let lesson = context.safeFetchFirst(request)
        lessonsByID[lessonID] = .some(lesson)
        return lesson
    }

    // MARK: - Sequence Activity

    /// What the child has done on one sequence: the presentations she was
    /// given, her work on its lessons and her notes about them.
    struct SequenceStats {
        let lessonAssignments: [CDLessonAssignment]
        let workModels: [CDWorkModel]
        let notes: [CDNote]
        let presentationCount: Int
        let workCount: Int
        let noteCount: Int
        let totalActivity: Int
        let lastActivityDate: Date?

        static let empty = SequenceStats(
            lessonAssignments: [], workModels: [], notes: [],
            presentationCount: 0, workCount: 0, noteCount: 0,
            totalActivity: 0, lastActivityDate: nil
        )
    }

    /// The stats for a card, from the load; recomputed only if the load
    /// hasn't happened yet.
    func stats(for standing: SequenceStanding) -> SequenceStats {
        if let cached = statsByStanding[standing.id] { return cached }
        guard let studentID, let context else { return .empty }
        return sequenceStats(for: standing, studentIDString: studentID.uuidString, context: context)
    }

    private func sequenceStats(
        for standing: SequenceStanding, studentIDString: String, context: NSManagedObjectContext
    ) -> SequenceStats {
        let lessonIDs = standing.lessons.compactMap { $0.id?.uuidString }
        guard !lessonIDs.isEmpty else { return .empty }

        let lessonAssignments = SequenceActivityFetches.presentedAssignments(
            studentID: studentIDString, lessonIDs: lessonIDs, in: context
        )
        let workModels = allWorkModels.filter { lessonIDs.contains($0.lessonID.uppercased()) }
        let notes = SequenceActivityFetches.notes(studentID: studentIDString, lessonIDs: lessonIDs, in: context)

        let presentationCount = lessonAssignments.count
        let workCount = workModels.count
        let noteCount = notes.count

        var dates: [Date] = []
        dates.append(contentsOf: lessonAssignments.compactMap(\.presentedAt))
        dates.append(contentsOf: workModels.compactMap { $0.completedAt ?? $0.createdAt })
        dates.append(contentsOf: notes.compactMap(\.updatedAt))
        if let last = standing.lastActivityAt { dates.append(last) }

        return SequenceStats(
            lessonAssignments: lessonAssignments,
            workModels: workModels,
            notes: notes,
            presentationCount: presentationCount,
            workCount: workCount,
            noteCount: noteCount,
            totalActivity: presentationCount + workCount + noteCount,
            lastActivityDate: dates.max()
        )
    }

    // MARK: - Report Helpers

    func reportTitle(for report: CDWorkModel) -> String {
        let title = report.title.trimmed()
        if !title.isEmpty { return title }
        if let lessonID = UUID(uuidString: report.lessonID),
           let lesson = lesson(for: lessonID) {
            return lesson.name
        }
        return "Untitled Report"
    }

    // MARK: - Color Helpers

    func trackColor(for title: String) -> Color {
        let hash = title.hash
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .mint, .teal, .cyan, .indigo
        ]
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

/// The fetches behind a sequence's activity counts and filter sheets, scoped
/// to one child and one sequence's lessons. Shared by the tab's view model
/// and `TrackFilteredListLoader`, so the card's count and the sheet's list
/// always agree.
enum SequenceActivityFetches {
    /// Presentations of the sequence's lessons that the child was given.
    /// Roster membership lives in an encoded blob, so it is checked in
    /// memory over the lesson-scoped rows.
    static func presentedAssignments(
        studentID: String, lessonIDs: [String], in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "lessonID IN[c] %@ AND stateRaw == %@",
            lessonIDs, LessonAssignmentState.presented.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "presentedAt", ascending: false)]
        return context.safeFetch(request).filter { $0.studentIDs.contains(studentID) }
    }

    /// The child's work on the sequence's lessons.
    static func work(studentID: String, lessonIDs: [String], in context: NSManagedObjectContext) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "studentID == %@ AND lessonID IN[c] %@", studentID, lessonIDs)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return context.safeFetch(request)
    }

    /// The child's notes about the sequence's lessons: a note names its
    /// children through `studentLinks`.
    static func notes(studentID: String, lessonIDs: [String], in context: NSManagedObjectContext) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(
            format: "lessonID IN[c] %@ AND ANY studentLinks.studentID ==[c] %@", lessonIDs, studentID
        )
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return context.safeFetch(request)
    }
}
