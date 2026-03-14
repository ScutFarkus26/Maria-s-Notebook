// ClassroomJobsViewModel.swift
// ViewModel for the Classroom Job Rotation Board.

import SwiftData
import SwiftUI

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
        students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor))

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

    func createJob(name: String, description: String, icon: String, colorRaw: String, maxStudents: Int, context: ModelContext) {
        let job = ClassroomJob(
            name: name,
            jobDescription: description,
            icon: icon,
            colorRaw: colorRaw,
            sortOrder: jobs.count,
            maxStudents: maxStudents
        )
        context.insert(job)
        context.safeSave()
        loadData(context: context)
    }

    func updateJob(_ job: ClassroomJob, name: String, description: String, icon: String, colorRaw: String, maxStudents: Int, context: ModelContext) {
        job.name = name
        job.jobDescription = description
        job.icon = icon
        job.colorRaw = colorRaw
        job.maxStudents = maxStudents
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
        let activeJobs = jobs.filter(\.isActive).sorted(by: { $0.sortOrder < $1.sortOrder })
        guard !activeJobs.isEmpty, !students.isEmpty else { return }

        let weekStart = currentWeekStart

        // Get last week's assignments to determine rotation
        let lastWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let lastWeekEnd = weekStart
        let lastWeekDescriptor = FetchDescriptor<JobAssignment>(
            predicate: #Predicate {
                $0.weekStartDate >= lastWeekStart && $0.weekStartDate < lastWeekEnd
            }
        )
        let lastWeekAssignments = context.safeFetch(lastWeekDescriptor)

        // Build mapping: jobID -> [studentID] from last week
        var lastWeekMap: [String: [String]] = [:]
        for assignment in lastWeekAssignments {
            lastWeekMap[assignment.jobID, default: []].append(assignment.studentID)
        }

        // Delete any existing assignments for current week
        let currentWeekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let currentDescriptor = FetchDescriptor<JobAssignment>(
            predicate: #Predicate {
                $0.weekStartDate >= weekStart && $0.weekStartDate < currentWeekEnd
            }
        )
        for existing in context.safeFetch(currentDescriptor) {
            context.delete(existing)
        }

        // Rotate: shift students to the next job
        let studentIDs = students.map { $0.id.uuidString }
        var usedStudents: Set<String> = []

        for (index, job) in activeJobs.enumerated() {
            let nextJobIndex = (index + 1) % activeJobs.count
            let nextJob = activeJobs[nextJobIndex]

            // Get students who were assigned to the next job last week
            let previousStudents = lastWeekMap[nextJob.id.uuidString] ?? []

            var assignees: [String] = []
            for studentID in previousStudents {
                if !usedStudents.contains(studentID) {
                    assignees.append(studentID)
                    usedStudents.insert(studentID)
                }
                if assignees.count >= job.maxStudents { break }
            }

            // Fill remaining slots with unassigned students
            if assignees.count < job.maxStudents {
                for studentID in studentIDs where !usedStudents.contains(studentID) {
                    assignees.append(studentID)
                    usedStudents.insert(studentID)
                    if assignees.count >= job.maxStudents { break }
                }
            }

            for studentID in assignees {
                let assignment = JobAssignment(
                    jobID: job.id.uuidString,
                    studentID: studentID,
                    weekStartDate: weekStart
                )
                context.insert(assignment)
            }
        }

        context.safeSave()
        loadData(context: context)
    }
}
