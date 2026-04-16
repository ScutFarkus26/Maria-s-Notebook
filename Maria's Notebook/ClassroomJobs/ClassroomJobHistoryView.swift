// ClassroomJobHistoryView.swift
// Shows historical job assignments grouped by week.

import SwiftUI
import CoreData

struct ClassroomJobHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDJobAssignment.weekStartDate, ascending: false)]) private var allAssignments: FetchedResults<CDJobAssignment>

    @FetchRequest(sortDescriptors: CDStudent.sortByName)private var allStudentsRaw: FetchedResults<CDStudent>

    private var allStudents: [CDStudent] { allStudentsRaw.filterEnrolled() }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDClassroomJob.sortOrder, ascending: true)]) private var allJobs: FetchedResults<CDClassroomJob>

    private var studentsByID: [UUID: CDStudent] {
        Dictionary(uniqueKeysWithValues: allStudents.compactMap { student in
            guard let id = student.id else { return nil }
            return (id, student)
        })
    }

    private var jobsByID: [UUID: CDClassroomJob] {
        Dictionary(uniqueKeysWithValues: allJobs.compactMap { job in
            guard let id = job.id else { return nil }
            return (id, job)
        })
    }

    private var assignmentsByWeek: [(week: Date, assignments: [CDJobAssignment])] {
        let grouped = Dictionary(grouping: allAssignments) { assignment in
            Calendar.current.startOfDay(for: assignment.weekStartDate ?? Date.distantPast)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (week: $0.key, assignments: $0.value) }
    }

    var body: some View {
        if assignmentsByWeek.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock.arrow.circlepath",
                description: Text("Job assignment history will appear here after rotations.")
            )
        } else {
            List {
                ForEach(assignmentsByWeek, id: \.week) { weekGroup in
                    Section {
                        ForEach(weekGroup.assignments, id: \.objectID) { assignment in
                            assignmentRow(assignment)
                        }
                    } header: {
                        Text(weekLabel(weekGroup.week))
                    }
                }
            }
        }
    }

    private func weekLabel(_ date: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "Week of \(date.formatted(fmt)) – \(end.formatted(fmt))"
    }

    private func assignmentRow(_ assignment: CDJobAssignment) -> some View {
        HStack(spacing: 8) {
            if let jobUUID = UUID(uuidString: assignment.jobID),
               let job = jobsByID[jobUUID] {
                Image(systemName: job.icon)
                    .font(.caption)
                    .foregroundStyle(job.color)
                    .frame(width: 24)

                Text(job.name)
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Text("Unknown Job")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let studentUUID = assignment.studentUUID,
               let student = studentsByID[studentUUID] {
                Text("\(student.firstName) \(student.lastName.prefix(1)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if assignment.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}
