// GoingOutDetailView.swift
// Detail view for a single Going-Out showing all sections.

import SwiftUI
import SwiftData

struct GoingOutDetailView: View {
    @Bindable var goingOut: GoingOut
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditor = false
    @State private var showingNoteEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status and header
                statusSection
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Info section
                if !goingOut.purpose.isEmpty || !goingOut.destination.isEmpty {
                    infoSection
                        .padding(.horizontal)
                }

                // Students
                if !goingOut.studentIDs.isEmpty {
                    studentsSection
                        .padding(.horizontal)
                }

                // Permission tracking
                permissionSection
                    .padding(.horizontal)

                // Planning checklist
                GoingOutChecklistSection(goingOut: goingOut)
                    .padding(.horizontal)
                    .cardStyle()
                    .padding(.horizontal)

                // Curriculum links
                GoingOutCurriculumLinkSection(goingOut: goingOut)
                    .padding(.horizontal)
                    .cardStyle()
                    .padding(.horizontal)

                // Follow-up work
                if !goingOut.followUpWork.isEmpty || goingOut.status == .completed {
                    followUpSection
                        .padding(.horizontal)
                }

                // Observation Notes
                observationNotesSection
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(goingOut.title.isEmpty ? "Going-Out" : goingOut.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            GoingOutEditorSheet(existingGoingOut: goingOut) { _ in }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NavigationStack {
                UnifiedNoteEditor(
                    context: .goingOut(goingOut),
                    initialNote: nil,
                    onSave: { _ in showingNoteEditor = false },
                    onCancel: { showingNoteEditor = false }
                )
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GoingOutStatusBadge(status: goingOut.status)
                Spacer()
                if let date = goingOut.proposedDate {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Status progression buttons
            statusProgressionButtons
        }
        .cardStyle()
    }

    private var statusProgressionButtons: some View {
        HStack(spacing: 8) {
            ForEach(availableTransitions, id: \.self) { newStatus in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        goingOut.status = newStatus
                        if newStatus == .completed {
                            goingOut.actualDate = Date()
                        }
                        modelContext.safeSave()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: newStatus.icon)
                            .font(.caption2)
                        Text(newStatus.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(newStatus.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(newStatus.color.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var availableTransitions: [GoingOutStatus] {
        switch goingOut.status {
        case .proposed: return [.planning, .cancelled]
        case .planning: return [.approved, .cancelled]
        case .approved: return [.completed, .cancelled]
        case .completed: return []
        case .cancelled: return [.proposed]
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !goingOut.destination.isEmpty {
                Label(goingOut.destination, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            if !goingOut.purpose.isEmpty {
                Text(goingOut.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Students Section

    private var studentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Students")
                .font(.subheadline)
                .fontWeight(.semibold)

            StudentChipsView(studentIDs: goingOut.studentUUIDs)
        }
        .cardStyle()
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        HStack(spacing: 10) {
            Text("Permission")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            Menu {
                ForEach(PermissionStatus.allCases) { status in
                    Button {
                        goingOut.permissionStatus = status
                        modelContext.safeSave()
                    } label: {
                        Label(status.displayName, systemImage: status.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: goingOut.permissionStatus.icon)
                        .font(.caption)
                    Text(goingOut.permissionStatus.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(goingOut.permissionStatus.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(goingOut.permissionStatus.color.opacity(0.12))
                )
            }
        }
        .cardStyle()
    }

    // MARK: - Follow-Up Section

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Follow-Up Work")
                .font(.subheadline)
                .fontWeight(.semibold)

            if goingOut.followUpWork.isEmpty {
                Text("No follow-up work recorded yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(goingOut.followUpWork)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Observation Notes Section

    private var observationNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Observation Notes")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                        Text("Add Note")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            let linkedNotes = goingOut.observationNotes ?? []
            if linkedNotes.isEmpty {
                Text("No observation notes yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(linkedNotes.sorted { $0.createdAt > $1.createdAt }) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Student Chips

private struct StudentChipsView: View {
    let studentIDs: [UUID]

    @Query(sort: Student.sortByName)
    private var allStudents: [Student]

    private var matchedStudents: [Student] {
        allStudents.filter { studentIDs.contains($0.id) }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(matchedStudents) { student in
                HStack(spacing: 4) {
                    Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                    Text(student.firstName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
        }
    }
}
