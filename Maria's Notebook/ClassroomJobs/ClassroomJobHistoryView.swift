// ClassroomJobHistoryView.swift
// Shows historical job assignments grouped by week.

import SwiftUI
import SwiftData

struct ClassroomJobHistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\JobAssignment.weekStartDate, order: .reverse)])
    private var allAssignments: [JobAssignment]

    @Query(sort: Student.sortByName)
    private var allStudentsRaw: [Student]

    private var allStudents: [Student] { allStudentsRaw.filter { $0.isEnrolled } }

    @Query(sort: [SortDescriptor(\ClassroomJob.sortOrder)])
    private var allJobs: [ClassroomJob]

    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: allStudents.map { ($0.id, $0) })
    }

    private var jobsByID: [UUID: ClassroomJob] {
        Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
    }

    private var assignmentsByWeek: [(week: Date, assignments: [JobAssignment])] {
        let grouped = Dictionary(grouping: allAssignments) { assignment in
            Calendar.current.startOfDay(for: assignment.weekStartDate)
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
                        ForEach(weekGroup.assignments) { assignment in
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

    private func assignmentRow(_ assignment: JobAssignment) -> some View {
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
