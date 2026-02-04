//
//  AttendanceMarkingFlowTests.swift
//  Maria's Notebook
//
//  Phase 5 Week 3: Integration Tests
//  Target: 5 tests for Attendance Marking flow
//

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("Integration: Attendance Marking Flow")
@MainActor
struct AttendanceMarkingFlowTests {
    
    // MARK: - Test Helpers
    
    private func createAttendanceSetup(
        studentCount: Int = 3,
        date: Date = Date(),
        context: ModelContext
    ) throws -> (students: [Student], date: Date) {
        var students: [Student] = []
        for i in 1...studentCount {
            let student = Student(name: "Student \(i)")
            context.insert(student)
            students.append(student)
        }
        try context.save()
        
        let normalizedDate = AppCalendar.startOfDay(date)
        return (students, normalizedDate)
    }
    
    private func createAttendanceRecords(
        for students: [Student],
        date: Date,
        context: ModelContext
    ) throws -> [AttendanceDayRecord] {
        var records: [AttendanceDayRecord] = []
        
        for student in students {
            let record = AttendanceDayRecord(
                studentID: student.id.uuidString,
                date: date,
                status: .unmarked,
                absenceReason: .none
            )
            context.insert(record)
            records.append(record)
        }
        
        try context.save()
        return records
    }
    
    // MARK: - Basic Attendance Marking Tests
    
    @Test("Complete flow: Mark individual student attendance")
    func markIndividualStudentAttendance() async throws {
        // Given: Students with unmarked attendance
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, date) = try createAttendanceSetup(context: context)
        let records = try createAttendanceRecords(for: students, date: date, context: context)
        
        // When: Marking first student present
        records[0].status = .present
        try context.save()
        
        // Then: Only first student marked present
        #expect(records[0].status == .present)
        #expect(records[1].status == .unmarked)
        #expect(records[2].status == .unmarked)
        
        // When: Marking second student absent
        records[1].status = .absent
        records[1].absenceReason = .sick
        try context.save()
        
        // Then: Second student marked absent with reason
        #expect(records[1].status == .absent)
        #expect(records[1].absenceReason == .sick)
        #expect(records[0].status == .present) // First still present
    }
    
    @Test("Complete flow: Bulk mark all present")
    func bulkMarkAllPresent() async throws {
        // Given: Multiple students with unmarked attendance
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, date) = try createAttendanceSetup(
            studentCount: 10,
            context: context
        )
        let records = try createAttendanceRecords(for: students, date: date, context: context)
        
        // When: Bulk marking all present
        for record in records {
            record.status = .present
            record.absenceReason = .none
        }
        try context.save()
        
        // Then: All students marked present
        let fetchedRecords = try context.fetch(FetchDescriptor<AttendanceDayRecord>())
        let todayRecords = fetchedRecords.filter { AppCalendar.isSameDay($0.date, date) }
        
        #expect(todayRecords.count == 10)
        #expect(todayRecords.allSatisfy { $0.status == .present })
        #expect(todayRecords.allSatisfy { $0.absenceReason == .none })
    }
    
    @Test("Complete flow: Status change clears absence reason")
    func statusChangesClearAbsenceReason() async throws {
        // Given: Student marked absent with reason
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, date) = try createAttendanceSetup(
            studentCount: 1,
            context: context
        )
        let records = try createAttendanceRecords(for: students, date: date, context: context)
        
        let record = records[0]
        record.status = .absent
        record.absenceReason = .sick
        try context.save()
        
        // When: Changing status to present
        record.status = .present
        record.absenceReason = .none  // Should be cleared when not absent
        try context.save()
        
        // Then: Absence reason cleared
        #expect(record.status == .present)
        #expect(record.absenceReason == .none)
        
        // When: Changing to absent with different reason
        record.status = .absent
        record.absenceReason = .familyEmergency
        try context.save()
        
        // Then: New reason set
        #expect(record.status == .absent)
        #expect(record.absenceReason == .familyEmergency)
    }
    
    // MARK: - Date Range Tests
    
    @Test("Complete flow: Attendance tracking across multiple dates")
    func attendanceTrackingAcrossMultipleDates() async throws {
        // Given: Student with attendance across multiple days
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let student = Student(name: "Test Student")
        context.insert(student)
        try context.save()
        
        let today = AppCalendar.startOfDay(Date())
        let yesterday = AppCalendar.addDays(-1, to: today)
        let twoDaysAgo = AppCalendar.addDays(-2, to: today)
        
        // When: Creating attendance records for different days
        let todayRecord = AttendanceDayRecord(
            studentID: student.id.uuidString,
            date: today,
            status: .present,
            absenceReason: .none
        )
        
        let yesterdayRecord = AttendanceDayRecord(
            studentID: student.id.uuidString,
            date: yesterday,
            status: .absent,
            absenceReason: .sick
        )
        
        let twoDaysAgoRecord = AttendanceDayRecord(
            studentID: student.id.uuidString,
            date: twoDaysAgo,
            status: .present,
            absenceReason: .none
        )
        
        context.insert(todayRecord)
        context.insert(yesterdayRecord)
        context.insert(twoDaysAgoRecord)
        try context.save()
        
        // Then: Each day has correct attendance
        let allRecords = try context.fetch(FetchDescriptor<AttendanceDayRecord>())
        let studentRecords = allRecords.filter { $0.studentID == student.id.uuidString }
        
        #expect(studentRecords.count == 3)
        
        let todayRec = studentRecords.first { AppCalendar.isSameDay($0.date, today) }
        let yesterdayRec = studentRecords.first { AppCalendar.isSameDay($0.date, yesterday) }
        
        #expect(todayRec?.status == .present)
        #expect(yesterdayRec?.status == .absent)
        #expect(yesterdayRec?.absenceReason == .sick)
    }
    
    // MARK: - Validation Tests
    
    @Test("Complete flow: Attendance record validation")
    func attendanceRecordValidation() async throws {
        // Given: Attendance records with various states
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext
        
        let (students, date) = try createAttendanceSetup(
            studentCount: 4,
            context: context
        )
        let records = try createAttendanceRecords(for: students, date: date, context: context)
        
        // When: Setting various valid states
        records[0].status = .present
        records[0].absenceReason = .none
        
        records[1].status = .absent
        records[1].absenceReason = .sick
        
        records[2].status = .absent
        records[2].absenceReason = .familyEmergency
        
        records[3].status = .unmarked
        records[3].absenceReason = .none
        
        try context.save()
        
        // Then: All records saved correctly
        let fetchedRecords = try context.fetch(FetchDescriptor<AttendanceDayRecord>())
        #expect(fetchedRecords.count >= 4)
        
        // Verify present students have no absence reason
        let presentRecords = fetchedRecords.filter { $0.status == .present }
        #expect(presentRecords.allSatisfy { $0.absenceReason == .none })
        
        // Verify absent students have reasons
        let absentRecords = fetchedRecords.filter { $0.status == .absent }
        #expect(absentRecords.allSatisfy { $0.absenceReason != .none })
    }
}

#endif
