// ClassroomJobsViewModel.swift
// ViewModel for the Classroom Job Rotation Board.

import SwiftData
import SwiftUI

struct ClassroomJobFields {
    var name: String
    var description: String
    var icon: String
    var colorRaw: String
    var maxStudents: Int
}

@Observable
@MainActor
final class ClassroomJobsViewModel {
    var jobs: [ClassroomJob] = []
    var currentAssignments: [UUID: [JobAssignment]] = [:]  // jobID -> assignments
    var students: [Student] = []
    var showingEditor = false
    var editingJob: ClassroomJob?
    var showingHistory = false

    var currentWeekStart: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    var weekDisplayString: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(currentWeekStart.formatted(fmt)) – \(end.formatted(fmt))"
    }

    func loadData(context: ModelContext) {
        let jobDescriptor = FetchDescriptor<ClassroomJob>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        jobs = context.safeFetch(jobDescriptor)

        let studentDescriptor = FetchDescriptor<Student>(sortBy: Student.sortByName)
        students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor).filter(\.isEnrolled))

        loadCurrentAssignments(context: context)
    }

    private func loadCurrentAssignments(context: ModelContext) {
        let weekStart = currentWeekStart
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let descriptor = FetchDescriptor<JobAssignment>(
            predicate: #Predicate {
                $0.weekStartDate >= weekStart && $0.weekStartDate < weekEnd
            }
        )
        let assignments = context.safeFetch(descriptor)
        currentAssignments = [:]
        for assignment in assignments {
            guard let jobUUID = UUID(uuidString: assignment.jobID) else { continue }
            currentAssignments[jobUUID, default: []].append(assignment)
        }
    }

    func studentName(for studentID: String) -> String? {
        guard let uuid = UUID(uuidString: studentID),
              let student = students.first(where: { $0.id == uuid }) else { return nil }
        return "\(student.firstName) \(student.lastName.prefix(1))."
    }

    func student(for studentID: String) -> Student? {
        guard let uuid = UUID(uuidString: studentID) else { return nil }
        return students.first(where: { $0.id == uuid })
    }

    // MARK: - CRUD

    func createJob(_ fields: ClassroomJobFields, context: ModelContext) {
        let job = ClassroomJob(
            name: fields.name,
            jobDescription: fields.description,
            icon: fields.icon,
            colorRaw: fields.colorRaw,
            sortOrder: jobs.count,
            maxStudents: fields.maxStudents
        )
        context.insert(job)
        context.safeSave()
        loadData(context: context)
    }

    func updateJob(_ job: ClassroomJob, with fields: ClassroomJobFields, context: ModelContext) {
        job.name = fields.name
        job.jobDescription = fields.description
        job.icon = fields.icon
        job.colorRaw = fields.colorRaw
        job.maxStudents = fields.maxStudents
        job.modifiedAt = Date()
        context.safeSave()
        loadData(context: context)
    }

    func deleteJob(_ job: ClassroomJob, context: ModelContext) {
        context.delete(job)
        context.safeSave()
        loadData(context: context)
    }

    func toggleAssignmentCompleted(_ assignment: JobAssignment, context: ModelContext) {
        assignment.isCompleted.toggle()
        assignment.modifiedAt = Date()
        context.safeSave()
    }

    // MARK: - Rotation

    func rotateJobs(context: ModelContext) {
        let activeJobs = jobs.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
        guard !activeJobs.isEmpty, !students.isEmpty else { return }

        let weekStart = currentWeekStart
        let lastWeekMap = fetchLastWeekMap(context: context, weekStart: weekStart)
        clearCurrentWeekAssignments(context: context, weekStart: weekStart)

        let studentIDs = students.map { $0.id.uuidString }
        var usedStudents: Set<String> = []

        for (index, job) in activeJobs.enumerated() {
            let nextJobIndex = (index + 1) % activeJobs.count
            let nextJob = activeJobs[nextJobIndex]
            let assignees = buildAssignees(
                for: job,
                previousStudents: lastWeekMap[nextJob.id.uuidString] ?? [],
                allStudentIDs: studentIDs,
                usedStudents: &usedStudents
            )
            for studentID in assignees {
                context.insert(JobAssignment(
                    jobID: job.id.uuidString,
                    studentID: studentID,
                    weekStartDate: weekStart
                ))
            }
        }

        context.safeSave()
        loadData(context: context)
    }

    // MARK: - Rotation Helpers

    private func fetchLastWeekMap(context: ModelContext, weekStart: Date) -> [String: [String]] {
        let lastWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let descriptor = FetchDescriptor<JobAssignment>(
            predicate: #Predicate {
                $0.weekStartDate >= lastWeekStart && $0.weekStartDate < weekStart
            }
        )
        var map: [String: [String]] = [:]
        for assignment in context.safeFetch(descriptor) {
            map[assignment.jobID, default: []].append(assignment.studentID)
        }
        return map
    }

    private func clearCurrentWeekAssignments(context: ModelContext, weekStart: Date) {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let descriptor = FetchDescriptor<JobAssignment>(
            predicate: #Predicate {
                $0.weekStartDate >= weekStart && $0.weekStartDate < weekEnd
            }
        )
        for existing in context.safeFetch(descriptor) {
            context.delete(existing)
        }
    }

    private func buildAssignees(
        for job: ClassroomJob,
        previousStudents: [String],
        allStudentIDs: [String],
        usedStudents: inout Set<String>
    ) -> [String] {
        var assignees: [String] = []
        for studentID in previousStudents {
            guard !usedStudents.contains(studentID) else { continue }
            assignees.append(studentID)
            usedStudents.insert(studentID)
            if assignees.count >= job.maxStudents { break }
        }
        if assignees.count < job.maxStudents {
            for studentID in allStudentIDs where !usedStudents.contains(studentID) {
                assignees.append(studentID)
                usedStudents.insert(studentID)
                if assignees.count >= job.maxStudents { break }
            }
        }
        return assignees
    }
}
