// StudentOverviewTab.swift
// Overview tab content extracted from StudentDetailView

import OSLog
import SwiftUI
import CoreData

private let logger = Logger.students

struct StudentOverviewTab: View {
    let student: CDStudent
    let isEditing: Bool
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftNickname: String
    @Binding var draftBirthday: Date
    @Binding var draftLevel: CDStudent.Level
    @Binding var draftStartDate: Date
    @Binding var draftEnrollmentStatus: CDStudent.EnrollmentStatus
    @Binding var draftDateWithdrawn: Date?
    @Binding var workCache: [CDWorkModel]
    @Binding var selectedWorkID: UUID?
    
    let lessonsByID: [UUID: CDLesson]
    let nextLessonsForStudent: [LessonAssignmentSnapshot]
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.calendar) private var calendar
    
    @State private var cachedAgeSchoolDays: [UUID: Int] = [:]
    
    private func lessonName(for work: CDWorkModel) -> String {
        lessonsByID[uuidString: work.lessonID]?.name ?? "Lesson"
    }
    
    private func studentDisplay(for work: CDWorkModel) -> String {
        return StudentFormatter.displayName(for: student)
    }
    
    private func needsAttention(for work: CDWorkModel) -> Bool {
        // Needs attention if overdue by due date, or last note is 10+ days old.
        if let due = work.dueAt {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(due) < today { return true }
        }
        if let lastNoteDate = latestNoteDate(for: work) {
            return daysSince(lastNoteDate) >= 10
        }
        // Use cached value to avoid repeated database queries during rendering
        let workID = work.id ?? UUID()
        let schoolDaysSinceCreated = cachedAgeSchoolDays[workID] ?? 0
        return schoolDaysSinceCreated >= 10
    }

    private func latestNoteDate(for work: CDWorkModel) -> Date? {
        let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
        return notes.compactMap { note in
            let updated = note.updatedAt ?? .distantPast
            let created = note.createdAt ?? .distantPast
            return max(updated, created)
        }.max()
    }

    private func daysSince(_ date: Date) -> Int {
        let start = AppCalendar.startOfDay(date)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
    
    private func ageDays(for work: CDWorkModel) -> Int {
        let start = AppCalendar.startOfDay(work.createdAt ?? Date())
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
    
    private func ageSchoolDays(for work: CDWorkModel) -> Int {
        // Use cached value to avoid repeated database queries during rendering
        return cachedAgeSchoolDays[work.id ?? UUID()] ?? 0
    }
    
    private func metadata(for work: CDWorkModel) -> String {
        var parts: [String] = []
        switch work.status {
        case .active: parts.append("Practice")
        case .review: parts.append("Follow-Up")
        case .complete: parts.append("Completed")
        }
        let age = ageDays(for: work)
        parts.append("\(age)d")
        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(spacing: 0) {
            StudentHeaderView(student: student)
                .padding(.top, 36)
            if isEditing {
                StudentEditForm(
                    draftFirstName: $draftFirstName,
                    draftLastName: $draftLastName,
                    draftNickname: $draftNickname,
                    draftBirthday: $draftBirthday,
                    draftLevel: $draftLevel,
                    draftStartDate: $draftStartDate,
                    draftEnrollmentStatus: $draftEnrollmentStatus,
                    draftDateWithdrawn: $draftDateWithdrawn
                )
            } else {
                if student.isWithdrawn {
                    WithdrawnBanner(dateWithdrawn: student.dateWithdrawn)
                }
                StudentInfoRows(student: student)
                
                Divider()
                    .padding(.top, AppTheme.Spacing.small)

                // Working on section
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Working on")
                        .font(.headline)
                        .padding(.horizontal, AppTheme.Spacing.xsmall)
                    if workCache.isEmpty {
                        Text("No active work.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Spacing.small)
                            .padding(.vertical, AppTheme.Spacing.compact)
                    } else {
                        ForEach(workCache, id: \.objectID) { work in
                            WorkCard.grid(
                                work: work,
                                lessonTitle: lessonName(for: work),
                                studentDisplay: studentDisplay(for: work),
                                needsAttention: needsAttention(for: work),
                                ageSchoolDays: ageSchoolDays(for: work),
                                onOpen: { w in
                                    selectedWorkID = w.id ?? UUID()
                                },
                                onMarkCompleted: { w in
                                    // Mark as complete
                                    w.status = .complete
                                    w.completedAt = AppCalendar.startOfDay(Date())
                                    do {
                                        try viewContext.save()
                                    } catch {
                                        logger.warning("Failed to save after marking work completed: \(error)")
                                    }
                                },
                                onScheduleToday: { w in
                                    // Schedule for today
                                    let today = AppCalendar.startOfDay(Date())
                                    w.dueAt = today
                                    do {
                                        try viewContext.save()
                                    } catch {
                                        logger.warning("Failed to save after scheduling for today: \(error)")
                                    }
                                }
                            )
                            .padding(.vertical, AppTheme.Spacing.xsmall)
                            .padding(.horizontal, AppTheme.Spacing.xsmall)
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.small)

                Divider()
                    .padding(.top, AppTheme.Spacing.small)

                NextLessonsSection(snapshots: nextLessonsForStudent, lessonsByID: lessonsByID)
            }
        }
        .task(id: workCache.map(\.objectID)) {
            await precomputeAgeValues()
        }
    }
    
    // MARK: - Performance Optimization
    
    /// Precompute age values once for all work items to avoid repeated database queries during rendering
    private func precomputeAgeValues() async {
        let cache = SchoolDayCalculationCache.shared
        let today = Date()
        
        guard !workCache.isEmpty else {
            cachedAgeSchoolDays = [:]
            return
        }
        
        // Find date range for all work items
        let allDates = workCache.map { work in
            WorkAgingPolicy.lastMeaningfulTouchDate(
                for: work,
                checkIns: (work.checkIns?.allObjects as? [CDWorkCheckIn]),
                notes: (work.unifiedNotes?.allObjects as? [CDNote])
            )
        }
        
        guard let minDate = allDates.min(), allDates.max() != nil else { return }
        
        // Preload school days cache for entire range
        cache.preloadNonSchoolDays(from: minDate, to: today, using: viewContext, calendar: calendar)
        
        // Compute all age values using cached data
        var result: [UUID: Int] = [:]
        for work in workCache {
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(
                for: work,
                checkIns: (work.checkIns?.allObjects as? [CDWorkCheckIn]),
                notes: (work.unifiedNotes?.allObjects as? [CDNote])
            )
            let age = cache.schoolDaysSinceCreation(
                createdAt: lastTouch, asOf: today,
                using: viewContext, calendar: calendar
            )
            if let workID = work.id { result[workID] = age }
        }
        
        cachedAgeSchoolDays = result
    }
}
