// StudentOverviewTab.swift
// Overview tab content extracted from StudentDetailView

import SwiftUI
import SwiftData

struct StudentOverviewTab: View {
    let student: Student
    let isEditing: Bool
    @Binding var draftFirstName: String
    @Binding var draftLastName: String
    @Binding var draftNickname: String
    @Binding var draftBirthday: Date
    @Binding var draftLevel: Student.Level
    @Binding var draftStartDate: Date
    @Binding var workCache: [WorkModel]
    @Binding var selectedWorkID: UUID?
    
    let lessonsByID: [UUID: Lesson]
    let nextLessonsForStudent: [StudentLessonSnapshot]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    
    @State private var cachedAgeSchoolDays: [UUID: Int] = [:]
    
    private func lessonName(for work: WorkModel) -> String {
        if let id = UUID(uuidString: work.lessonID), let lesson = lessonsByID[id] {
            return lesson.name
        }
        return "Lesson"
    }
    
    private func studentDisplay(for work: WorkModel) -> String {
        return StudentFormatter.displayName(for: student)
    }
    
    private func needsAttention(for work: WorkModel) -> Bool {
        // Needs attention if overdue by due date, or last note is 10+ days old.
        if let due = work.dueAt {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(due) < today { return true }
        }
        if let lastNoteDate = latestNoteDate(for: work) {
            return daysSince(lastNoteDate) >= 10
        }
        // Use cached value to avoid repeated database queries during rendering
        let schoolDaysSinceCreated = cachedAgeSchoolDays[work.id] ?? 0
        return schoolDaysSinceCreated >= 10
    }

    private func latestNoteDate(for work: WorkModel) -> Date? {
        let notes = work.unifiedNotes ?? []
        return notes.map { max($0.updatedAt, $0.createdAt) }.max()
    }

    private func daysSince(_ date: Date) -> Int {
        let start = AppCalendar.startOfDay(date)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
    
    private func ageDays(for work: WorkModel) -> Int {
        let start = AppCalendar.startOfDay(work.createdAt)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
    
    private func ageSchoolDays(for work: WorkModel) -> Int {
        // Use cached value to avoid repeated database queries during rendering
        return cachedAgeSchoolDays[work.id] ?? 0
    }
    
    private func metadata(for work: WorkModel) -> String {
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
                    draftStartDate: $draftStartDate
                )
            } else {
                StudentInfoRows(student: student)
                
                Divider()
                    .padding(.top, 8)

                // Working on section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Working on")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    if workCache.isEmpty {
                        Text("No active work.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(workCache, id: \.id) { work in
                            WorkCard.grid(
                                work: work,
                                lessonTitle: lessonName(for: work),
                                studentDisplay: studentDisplay(for: work),
                                needsAttention: needsAttention(for: work),
                                ageSchoolDays: ageSchoolDays(for: work),
                                onOpen: { w in
                                    selectedWorkID = w.id
                                },
                                onMarkCompleted: { w in
                                    // Mark as complete
                                    w.status = .complete
                                    w.completedAt = AppCalendar.startOfDay(Date())
                                    try? modelContext.save()
                                },
                                onScheduleToday: { w in
                                    // Schedule for today
                                    let today = AppCalendar.startOfDay(Date())
                                    w.dueAt = today
                                    try? modelContext.save()
                                }
                            )
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 8)

                Divider()
                    .padding(.top, 8)

                NextLessonsSection(snapshots: nextLessonsForStudent, lessonsByID: lessonsByID)
            }
        }
        .task(id: workCache.map { $0.id }) {
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
            WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: work.checkIns, notes: work.unifiedNotes)
        }
        
        guard let minDate = allDates.min(), let _ = allDates.max() else { return }
        
        // Preload school days cache for entire range
        cache.preloadNonSchoolDays(from: minDate, to: today, using: modelContext, calendar: calendar)
        
        // Compute all age values using cached data
        var result: [UUID: Int] = [:]
        for work in workCache {
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: work.checkIns, notes: work.unifiedNotes)
            let age = cache.schoolDaysSinceCreation(createdAt: lastTouch, asOf: today, using: modelContext, calendar: calendar)
            result[work.id] = age
        }
        
        cachedAgeSchoolDays = result
    }
}
