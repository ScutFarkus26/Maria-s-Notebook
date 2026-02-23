#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory for TodayViewModel Tests

@MainActor
func makeTodayViewModelContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        AttendanceRecord.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        Note.self,
        Document.self,
        Reminder.self,
        CalendarEvent.self,
        GroupTrack.self,
        StudentTrackEnrollment.self,
    ])
}

// MARK: - TodayViewModel Test Assertions

/// Asserts that a TodayViewModel has empty initial state
@MainActor
func expectEmptyViewModel(_ vm: TodayViewModel, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(vm.todaysLessons.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.overdueSchedule.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.todaysSchedule.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.staleFollowUps.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.studentsByID.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.lessonsByID.isEmpty, sourceLocation: sourceLocation)
}

/// Asserts that attendance summary has zero counts
@MainActor
func expectZeroAttendance(_ vm: TodayViewModel, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(vm.attendanceSummary.presentCount == 0, sourceLocation: sourceLocation)
    #expect(vm.attendanceSummary.tardyCount == 0, sourceLocation: sourceLocation)
    #expect(vm.attendanceSummary.absentCount == 0, sourceLocation: sourceLocation)
    #expect(vm.attendanceSummary.leftEarlyCount == 0, sourceLocation: sourceLocation)
    #expect(vm.absentToday.isEmpty, sourceLocation: sourceLocation)
    #expect(vm.leftEarlyToday.isEmpty, sourceLocation: sourceLocation)
}

#endif
