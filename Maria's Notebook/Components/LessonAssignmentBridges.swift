// LessonAssignmentBridges.swift
// Temporary bridge views that look up legacy StudentLesson records
// for views that haven't been migrated to LessonAssignment yet.
// These will be removed once StudentLessonDetailView and
// StudentLessonQuickActionsView are migrated directly.

import SwiftUI
import SwiftData

// MARK: - Detail Bridge

struct LessonAssignmentDetailBridge: View {
    @Environment(\.modelContext) private var modelContext
    let lessonAssignment: LessonAssignment
    let onDone: () -> Void

    var body: some View {
        if let sl = findStudentLesson() {
            StudentLessonDetailView(studentLesson: sl, onDone: onDone)
        } else {
            ContentUnavailableView("Detail Unavailable", systemImage: "doc.questionmark")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
    }

    private func findStudentLesson() -> StudentLesson? {
        if let legacyID = lessonAssignment.migratedFromStudentLessonID,
           let uuid = UUID(uuidString: legacyID) {
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { $0.id == uuid }
            )
            if let sl = try? modelContext.fetch(descriptor).first {
                return sl
            }
        }
        let lessonID = lessonAssignment.lessonID
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.lessonID == lessonID }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let studentIDStrings = lessonAssignment.studentIDs
        return candidates.first { Set($0.studentIDs) == Set(studentIDStrings) }
    }
}

// MARK: - Quick Actions Bridge

struct LessonAssignmentQuickActionsBridge: View {
    @Environment(\.modelContext) private var modelContext
    let lessonAssignment: LessonAssignment
    let onDone: () -> Void

    var body: some View {
        if let sl = findStudentLesson() {
            StudentLessonQuickActionsView(studentLesson: sl, onDone: onDone)
        } else {
            ContentUnavailableView("Quick Actions Unavailable", systemImage: "bolt.slash")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
    }

    private func findStudentLesson() -> StudentLesson? {
        if let legacyID = lessonAssignment.migratedFromStudentLessonID,
           let uuid = UUID(uuidString: legacyID) {
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { $0.id == uuid }
            )
            if let sl = try? modelContext.fetch(descriptor).first {
                return sl
            }
        }
        let lessonID = lessonAssignment.lessonID
        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { $0.lessonID == lessonID }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let studentIDStrings = lessonAssignment.studentIDs
        return candidates.first { Set($0.studentIDs) == Set(studentIDStrings) }
    }
}
