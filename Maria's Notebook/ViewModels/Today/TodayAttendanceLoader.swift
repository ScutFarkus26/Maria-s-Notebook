// TodayAttendanceLoader.swift
// Handles loading and processing attendance data for the Today view.
// Encapsulates the attendance aggregation logic used by TodayViewModel.

import Foundation
import SwiftData

// MARK: - Today Attendance Loader

/// Loader for processing attendance data into summaries and ID lists.
enum TodayAttendanceLoader {

    // MARK: - Types

    /// Result of processing attendance data.
    struct AttendanceResult {
        let summary: AttendanceSummary
        let absentStudentIDs: [UUID]
        let leftEarlyStudentIDs: [UUID]
    }

    // MARK: - Load Attendance

    /// Processes attendance records for a specific day and level filter.
    /// - Parameters:
    ///   - records: Attendance records to process
    ///   - studentsByID: Cached students for level filtering
    ///   - levelFilter: Current level filter
    /// - Returns: Processed attendance result with summary and ID lists
    static func processAttendance(
        records: [AttendanceRecord],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter
    ) -> AttendanceResult {
        var present = 0
        var tardy = 0
        var absent = 0
        var leftEarly = 0
        var absentIDs: Set<UUID> = []
        var leftEarlyIDs: Set<UUID> = []

        for rec in records {
            guard let studentIDUUID = rec.studentID.asUUID,
                  let s = studentsByID[studentIDUUID] else { continue }
            if !levelFilter.matches(s.level) { continue }

            switch rec.status {
            case .present:
                present += 1
            case .tardy:
                tardy += 1
            case .absent:
                absent += 1
                absentIDs.insert(studentIDUUID)
            case .leftEarly:
                leftEarly += 1
                leftEarlyIDs.insert(studentIDUUID)
            case .unmarked:
                break
            }
        }

        let summary = AttendanceSummary(
            presentCount: present + tardy,
            tardyCount: tardy,
            absentCount: absent,
            leftEarlyCount: leftEarly
        )

        return AttendanceResult(
            summary: summary,
            absentStudentIDs: Array(absentIDs),
            leftEarlyStudentIDs: Array(leftEarlyIDs)
        )
    }
}
