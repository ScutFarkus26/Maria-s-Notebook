// ClassroomJobsViewModel.swift
// ViewModel for the Classroom Job Rotation Board.

import CoreData
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
    var jobs: [CDClassroomJob] = []
    var currentAssignments: [UUID: [CDJobAssignment]] = [:]  // jobID -> assignments
    var students: [CDStudent] = []
    var showingEditor = false
    var editingJob: CDClassroomJob?
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

    func loadData(context: NSManagedObjectContext) {
        let jobDescriptor: NSFetchRequest<CDClassroomJob> = CDClassroomJob.fetchRequest() as! NSFetchRequest<CDClassroomJob>
        jobDescriptor.sortDescriptors = [NSSortDescriptor(keyPath: \CDClassroomJob.sortOrder, ascending: true)]
        jobs = context.safeFetch(jobDescriptor)

        let studentDescriptor = { let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.sortDescriptors = CDStudent.sortByName; return r }()
        students = TestStudentsFilter.filterVisible(context.safeFetch(studentDescriptor).filter(\.isEnrolled))

        loadCurrentAssignments(context: context)
    }

    private func loadCurrentAssignments(context: NSManagedObjectContext) {
        let weekStart = currentWeekStart
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let descriptor: NSFetchRequest<CDJobAssignment> = CDJobAssignment.fetchRequest() as! NSFetchRequest<CDJobAssignment>
        descriptor.predicate = NSPredicate(format: "weekStartDate >= %@ AND weekStartDate < %@", weekStart as CVarArg, weekEnd as CVarArg)
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

    func student(for studentID: String) -> CDStudent? {
        guard let uuid = UUID(uuidString: studentID) else { return nil }
        return students.first(where: { $0.id == uuid })
    }

    // MARK: - CRUD

    func createJob(_ fields: ClassroomJobFields, context: NSManagedObjectContext) {
        let job = CDClassroomJob(context: context)
        job.name = fields.name
        job.jobDescription = fields.description
        job.icon = fields.icon
        job.colorRaw = fields.colorRaw
        job.sortOrder = Int64(jobs.count)
        job.maxStudents = Int64(fields.maxStudents)
        context.safeSave()
        loadData(context: context)
    }

    func updateJob(_ job: CDClassroomJob, with fields: ClassroomJobFields, context: NSManagedObjectContext) {
        job.name = fields.name
        job.jobDescription = fields.description
        job.icon = fields.icon
        job.colorRaw = fields.colorRaw
        job.maxStudents = Int64(fields.maxStudents)
        job.modifiedAt = Date()
        context.safeSave()
        loadData(context: context)
    }

    func deleteJob(_ job: CDClassroomJob, context: NSManagedObjectContext) {
        context.delete(job)
        context.safeSave()
        loadData(context: context)
    }

    func toggleAssignmentCompleted(_ assignment: CDJobAssignment, context: NSManagedObjectContext) {
        assignment.isCompleted.toggle()
        assignment.modifiedAt = Date()
        context.safeSave()
    }

    // MARK: - Rotation

    func rotateJobs(context: NSManagedObjectContext) {
        let activeJobs = jobs.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
        guard !activeJobs.isEmpty, !students.isEmpty else { return }

        let weekStart = currentWeekStart
        let lastWeekMap = fetchLastWeekMap(context: context, weekStart: weekStart)
        clearCurrentWeekAssignments(context: context, weekStart: weekStart)

        let studentIDs = students.compactMap { $0.id?.uuidString }
        var usedStudents: Set<String> = []

        for (index, job) in activeJobs.enumerated() {
            let nextJobIndex = (index + 1) % activeJobs.count
            let nextJob = activeJobs[nextJobIndex]
            let assignees = buildAssignees(
                for: job,
                previousStudents: lastWeekMap[nextJob.id?.uuidString ?? ""] ?? [],
                allStudentIDs: studentIDs,
                usedStudents: &usedStudents
            )
            for studentID in assignees {
                let assignment = CDJobAssignment(context: context)
                assignment.jobID = job.id?.uuidString ?? ""
                assignment.studentID = studentID
                assignment.weekStartDate = weekStart
            }
        }

        context.safeSave()
        loadData(context: context)
    }

    // MARK: - Rotation Helpers

    private func fetchLastWeekMap(context: NSManagedObjectContext, weekStart: Date) -> [String: [String]] {
        let lastWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let descriptor: NSFetchRequest<CDJobAssignment> = CDJobAssignment.fetchRequest() as! NSFetchRequest<CDJobAssignment>
        descriptor.predicate = NSPredicate(format: "weekStartDate >= %@ AND weekStartDate < %@", lastWeekStart as CVarArg, weekStart as CVarArg)
        var map: [String: [String]] = [:]
        for assignment in context.safeFetch(descriptor) {
            map[assignment.jobID, default: []].append(assignment.studentID)
        }
        return map
    }

    private func clearCurrentWeekAssignments(context: NSManagedObjectContext, weekStart: Date) {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let descriptor: NSFetchRequest<CDJobAssignment> = CDJobAssignment.fetchRequest() as! NSFetchRequest<CDJobAssignment>
        descriptor.predicate = NSPredicate(format: "weekStartDate >= %@ AND weekStartDate < %@", weekStart as CVarArg, weekEnd as CVarArg)
        for existing in context.safeFetch(descriptor) {
            context.delete(existing)
        }
    }

    private func buildAssignees(
        for job: CDClassroomJob,
        previousStudents: [String],
        allStudentIDs: [String],
        usedStudents: inout Set<String>
    ) -> [String] {
        var assignees: [String] = []
        for studentID in previousStudents {
            guard !usedStudents.contains(studentID) else { continue }
            assignees.append(studentID)
            usedStudents.insert(studentID)
            if assignees.count >= Int(job.maxStudents) { break }
        }
        if assignees.count < Int(job.maxStudents) {
            for studentID in allStudentIDs where !usedStudents.contains(studentID) {
                assignees.append(studentID)
                usedStudents.insert(studentID)
                if assignees.count >= Int(job.maxStudents) { break }
            }
        }
        return assignees
    }
}
