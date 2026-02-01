//
//  LessonAssignmentBackupTests.swift
//  Maria's Notebook
//
//  Tests for LessonAssignment backup/restore functionality.
//  Verifies Phase 6 migration: backup system integration.
//

import Foundation
import SwiftData

#if canImport(Testing)
import Testing
@testable import Maria_s_Notebook

@Suite("LessonAssignment Backup Tests")
@MainActor
struct LessonAssignmentBackupTests {

    // MARK: - DTO Transformation Tests

    @Test("LessonAssignment transforms to DTO with all fields")
    func lessonAssignmentToDTO() throws {
        let lessonID = UUID()
        let studentIDs = [UUID(), UUID()]

        let assignment = LessonAssignment(
            id: UUID(),
            createdAt: Date(),
            state: .presented,
            scheduledFor: Date(),
            presentedAt: Date(),
            lessonID: lessonID,
            studentIDs: studentIDs,
            lesson: nil,
            needsPractice: true,
            needsAnotherPresentation: false,
            followUpWork: "Review chapter 3",
            notes: "Great session",
            trackID: "track-123",
            trackStepID: "step-456"
        )
        assignment.lessonTitleSnapshot = "Math Basics"
        assignment.lessonSubheadingSnapshot = "Addition"
        assignment.migratedFromStudentLessonID = "sl-789"
        assignment.migratedFromPresentationID = "pres-012"

        let dto = BackupDTOTransformers.toDTO(assignment)

        #expect(dto.id == assignment.id)
        #expect(dto.stateRaw == "presented")
        #expect(dto.lessonID == lessonID.uuidString)
        #expect(dto.studentIDs.count == 2)
        #expect(dto.needsPractice == true)
        #expect(dto.needsAnotherPresentation == false)
        #expect(dto.followUpWork == "Review chapter 3")
        #expect(dto.notes == "Great session")
        #expect(dto.lessonTitleSnapshot == "Math Basics")
        #expect(dto.lessonSubheadingSnapshot == "Addition")
        #expect(dto.trackID == "track-123")
        #expect(dto.trackStepID == "step-456")
        #expect(dto.migratedFromStudentLessonID == "sl-789")
        #expect(dto.migratedFromPresentationID == "pres-012")
    }

    @Test("Batch transformation converts multiple assignments")
    func batchDTOTransformation() throws {
        let assignments = [
            LessonAssignment(lessonID: UUID(), studentIDs: [UUID()]),
            LessonAssignment(lessonID: UUID(), studentIDs: [UUID(), UUID()]),
            LessonAssignment(lessonID: UUID(), studentIDs: [])
        ]

        let dtos = BackupDTOTransformers.toDTOs(assignments)

        #expect(dtos.count == 3)
        #expect(dtos[0].studentIDs.count == 1)
        #expect(dtos[1].studentIDs.count == 2)
        #expect(dtos[2].studentIDs.count == 0)
    }

    // MARK: - DTO Encoding/Decoding Tests

    @Test("LessonAssignmentDTO encodes and decodes correctly")
    func lessonAssignmentDTOEncodeDecode() throws {
        let original = LessonAssignmentDTO(
            id: UUID(),
            createdAt: Date(),
            modifiedAt: Date(),
            stateRaw: "scheduled",
            scheduledFor: Date(),
            presentedAt: nil,
            lessonID: UUID().uuidString,
            studentIDs: [UUID().uuidString, UUID().uuidString],
            lessonTitleSnapshot: "Test Lesson",
            lessonSubheadingSnapshot: "Subheading",
            needsPractice: true,
            needsAnotherPresentation: false,
            followUpWork: "Practice worksheet",
            notes: "Good progress",
            trackID: nil,
            trackStepID: nil,
            migratedFromStudentLessonID: nil,
            migratedFromPresentationID: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LessonAssignmentDTO.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.stateRaw == original.stateRaw)
        #expect(decoded.lessonID == original.lessonID)
        #expect(decoded.studentIDs == original.studentIDs)
        #expect(decoded.lessonTitleSnapshot == original.lessonTitleSnapshot)
        #expect(decoded.needsPractice == original.needsPractice)
        #expect(decoded.followUpWork == original.followUpWork)
    }

    @Test("BackupPayload includes lessonAssignments in round-trip")
    func backupPayloadWithLessonAssignments() throws {
        let lessonAssignmentDTOs = [
            LessonAssignmentDTO(
                id: UUID(),
                createdAt: Date(),
                modifiedAt: Date(),
                stateRaw: "presented",
                scheduledFor: nil,
                presentedAt: Date(),
                lessonID: UUID().uuidString,
                studentIDs: [UUID().uuidString],
                lessonTitleSnapshot: "Lesson 1",
                lessonSubheadingSnapshot: nil,
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: "",
                notes: "",
                trackID: nil,
                trackStepID: nil,
                migratedFromStudentLessonID: nil,
                migratedFromPresentationID: nil
            )
        ]

        let payload = BackupPayload(
            items: [],
            students: [],
            lessons: [],
            studentLessons: [],
            lessonAssignments: lessonAssignmentDTOs,
            workPlanItems: [],
            scopedNotes: [],
            notes: [],
            nonSchoolDays: [],
            schoolDayOverrides: [],
            studentMeetings: [],
            presentations: [],
            communityTopics: [],
            proposedSolutions: [],
            meetingNotes: [],
            communityAttachments: [],
            attendance: [],
            workCompletions: [],
            projects: [],
            projectAssignmentTemplates: [],
            projectSessions: [],
            projectRoles: [],
            projectTemplateWeeks: [],
            projectWeekRoleAssignments: [],
            preferences: PreferencesDTO(values: [:])
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        #expect(decoded.lessonAssignments.count == 1)
        #expect(decoded.lessonAssignments[0].lessonTitleSnapshot == "Lesson 1")
    }

    @Test("Old backups without lessonAssignments decode with empty array")
    func backwardCompatibility_OldBackupWithoutLessonAssignments() throws {
        // Simulate an old backup JSON that doesn't have the lessonAssignments key
        let oldBackupJSON = """
        {
            "items": [],
            "students": [],
            "lessons": [],
            "studentLessons": [],
            "workPlanItems": [],
            "scopedNotes": [],
            "notes": [],
            "nonSchoolDays": [],
            "schoolDayOverrides": [],
            "studentMeetings": [],
            "presentations": [],
            "communityTopics": [],
            "proposedSolutions": [],
            "meetingNotes": [],
            "communityAttachments": [],
            "attendance": [],
            "workCompletions": [],
            "projects": [],
            "projectAssignmentTemplates": [],
            "projectSessions": [],
            "projectRoles": [],
            "projectTemplateWeeks": [],
            "projectWeekRoleAssignments": [],
            "preferences": { "values": {} }
        }
        """

        let data = oldBackupJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(BackupPayload.self, from: data)
        #expect(payload.lessonAssignments.count == 0)
    }

    // MARK: - State Preservation Tests

    @Test("All LessonAssignment states are preserved in DTO", arguments: LessonAssignmentState.allCases)
    func allStatesPreserved(state: LessonAssignmentState) throws {
        let assignment = LessonAssignment(
            state: state,
            lessonID: UUID(),
            studentIDs: [UUID()]
        )

        let dto = BackupDTOTransformers.toDTO(assignment)
        #expect(dto.stateRaw == state.rawValue, "State \(state) not preserved in DTO")

        let parsedState = LessonAssignmentState(rawValue: dto.stateRaw)
        #expect(parsedState == state, "State \(state) not parseable from DTO")
    }

    // MARK: - Migration Data Integrity Tests

    @Test("Migration tracking fields are preserved")
    func migrationTrackingFieldsPreserved() throws {
        let assignment = LessonAssignment(lessonID: UUID(), studentIDs: [])
        assignment.migratedFromStudentLessonID = "original-sl-id"
        assignment.migratedFromPresentationID = "original-pres-id"

        let dto = BackupDTOTransformers.toDTO(assignment)

        #expect(dto.migratedFromStudentLessonID == "original-sl-id")
        #expect(dto.migratedFromPresentationID == "original-pres-id")
    }

    // MARK: - Edge Cases

    @Test("Empty studentIDs array is preserved")
    func emptyStudentIDs() throws {
        let assignment = LessonAssignment(lessonID: UUID(), studentIDs: [])
        let dto = BackupDTOTransformers.toDTO(assignment)

        #expect(dto.studentIDs.isEmpty)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LessonAssignmentDTO.self, from: data)

        #expect(decoded.studentIDs.isEmpty)
    }

    @Test("Nil optional fields encode and decode correctly")
    func nilOptionalFields() throws {
        let dto = LessonAssignmentDTO(
            id: UUID(),
            createdAt: Date(),
            modifiedAt: Date(),
            stateRaw: "draft",
            scheduledFor: nil,
            presentedAt: nil,
            lessonID: UUID().uuidString,
            studentIDs: [],
            lessonTitleSnapshot: nil,
            lessonSubheadingSnapshot: nil,
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: "",
            notes: "",
            trackID: nil,
            trackStepID: nil,
            migratedFromStudentLessonID: nil,
            migratedFromPresentationID: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LessonAssignmentDTO.self, from: data)

        #expect(decoded.scheduledFor == nil)
        #expect(decoded.presentedAt == nil)
        #expect(decoded.lessonTitleSnapshot == nil)
        #expect(decoded.trackID == nil)
    }

    @Test("Large studentIDs array (30 students) is preserved")
    func largeStudentIDList() throws {
        let studentIDs = (0..<30).map { _ in UUID() }
        let assignment = LessonAssignment(lessonID: UUID(), studentIDs: studentIDs)

        let dto = BackupDTOTransformers.toDTO(assignment)
        #expect(dto.studentIDs.count == 30)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LessonAssignmentDTO.self, from: data)

        #expect(decoded.studentIDs.count == 30)
    }
}

// MARK: - View Data Integrity Tests

@Suite("LessonAssignment View Tests")
struct LessonAssignmentViewTests {

    @Test("Resolved properties fall back to snapshot when relationship is nil")
    func resolvedPropertiesWithMissingRelationship() throws {
        let assignment = LessonAssignment(
            lessonID: UUID(),
            studentIDs: [UUID(), UUID()]
        )
        assignment.lessonTitleSnapshot = "Snapshot Title"
        assignment.lesson = nil

        #expect(assignment.displayTitle == "Snapshot Title")
        #expect(assignment.studentCount == 2)
    }

    @Test("displayTitle falls back to 'Unknown Lesson' when no data available")
    func displayTitleFallback() throws {
        let assignment = LessonAssignment(
            lessonID: UUID(),
            studentIDs: []
        )
        assignment.lessonTitleSnapshot = nil
        assignment.lesson = nil

        #expect(assignment.displayTitle == "Unknown Lesson")
    }
}

#endif
