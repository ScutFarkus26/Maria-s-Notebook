// ClassroomJobCard.swift
// Card displaying a single classroom job with assigned students.

import SwiftUI
import SwiftData

struct ClassroomJobCard: View {
    let job: ClassroomJob
    let assignments: [JobAssignment]
    let viewModel: ClassroomJobsViewModel
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: job.icon)
                    .font(.title3)
                    .foregroundStyle(job.color)
                    .frame(width: 32, height: 32)
                    .background(job.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(job.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !job.jobDescription.isEmpty {
                        Text(job.jobDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !job.isActive {
                    Text("Inactive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }

                Menu {
                    Button {
                        viewModel.editingJob = job
                        viewModel.showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        viewModel.deleteJob(job, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }

            // Assigned students
            if assignments.isEmpty {
                Text("No student assigned")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 40)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(assignments) { assignment in
                        assignmentChip(assignment)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .cardStyle()
    }

    private func assignmentChip(_ assignment: JobAssignment) -> some View {
        HStack(spacing: 4) {
            if let student = viewModel.student(for: assignment.studentID) {
                Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                Text(student.firstName)
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Text("Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.toggleAssignmentCompleted(assignment, context: modelContext)
            } label: {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(assignment.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
