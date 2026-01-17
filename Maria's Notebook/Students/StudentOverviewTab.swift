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
    @Binding var contractsCache: [WorkModel]
    @Binding var selectedWorkID: UUID?
    
    let lessonsByID: [UUID: Lesson]
    let nextLessonsForStudent: [StudentLessonSnapshot]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    
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
        // Conservative heuristic: overdue if dueAt in past, or stale if older than 10 days and no schedule.
        if let due = work.dueAt {
            let today = AppCalendar.startOfDay(Date())
            if AppCalendar.startOfDay(due) < today { return true }
        }
        let age = ageDays(for: work)
        if age >= 10 { return true }
        return false
    }
    
    private func ageDays(for work: WorkModel) -> Int {
        let start = AppCalendar.startOfDay(work.createdAt)
        let now = AppCalendar.startOfDay(Date())
        let comps = AppCalendar.shared.dateComponents([.day], from: start, to: now)
        return comps.day ?? 0
    }
    
    private func ageSchoolDays(for work: WorkModel) -> Int {
        let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: work.checkIns, notes: work.unifiedNotes)
        return LessonAgeHelper.schoolDaysSinceCreation(createdAt: lastTouch, asOf: Date(), using: modelContext, calendar: calendar)
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
                    if contractsCache.isEmpty {
                        Text("No active work.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(contractsCache, id: \.id) { work in
                            WorkCardView(
                                work: work,
                                lessonTitle: lessonName(for: work),
                                studentDisplay: studentDisplay(for: work),
                                needsAttention: needsAttention(for: work),
                                metadata: metadata(for: work),
                                ageSchoolDays: ageSchoolDays(for: work),
                                onOpen: { w in
                                    selectedWorkID = w.id
                                },
                                onMarkCompleted: { w in
                                    // Mark as complete
                                    w.status = .complete
                                    w.completedAt = Date()
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
    }
}

