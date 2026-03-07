import SwiftUI
import SwiftData

// MARK: - Content Mode Sections

extension ProjectSessionDetailView {

    // MARK: - Choice Mode Content

    @ViewBuilder
    var choiceModeContent: some View {
        // Offered works section
        Section("Offered Works") {
            ForEach(offeredWorks) { work in
                offeredWorkRow(work)
            }

            Button {
                showAddWorkSheet = true
            } label: {
                Label("Add Work Offer", systemImage: "plus.circle.fill")
            }
        }

        // Student selection status
        Section("Student Selections") {
            ForEach(projectMemberIDs.sorted { studentName(for: $0) < studentName(for: $1) }, id: \.self) { studentID in
                studentSelectionRow(studentID: studentID)
            }
        }
    }

    @ViewBuilder
    func offeredWorkRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(work.title.isEmpty ? "Untitled" : work.title)
                    .font(.headline)
                Spacer()
                let count = work.selectedStudentIDs.count
                Label("\(count) selected", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !work.latestUnifiedNoteText.isEmpty {
                Text(work.latestUnifiedNoteText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let due = work.dueAt {
                Label {
                    Text(due, format: Date.FormatStyle().month().day())
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func studentSelectionRow(studentID: String) -> some View {
        let selectedWorks = sessionWorkModels.filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
        }
        let count = selectedWorks.count
        let min = session.minSelections
        let isComplete = count >= min

        Button {
            showSelectionSheetForStudent = studentID
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName(for: studentID))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !selectedWorks.isEmpty {
                        Text(selectedWorks.map { $0.title.isEmpty ? "Untitled" : $0.title }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(count)/\(min)")
                        .font(.caption)
                        .foregroundStyle(isComplete ? .green : .orange)
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete ? .green : .orange)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Uniform Mode Content

    @ViewBuilder
    var uniformModeContent: some View {
        if groupedByStudent.isEmpty {
            ContentUnavailableView(
                "No Work",
                systemImage: "doc.text",
                description: Text("No work items are linked to this session.")
            )
        } else {
            ForEach(groupedByStudent, id: \.id) { bucket in
                Section(header: Text(studentName(for: bucket.id)).font(.headline)) {
                    ForEach(bucket.items, id: \.id) { work in
                        workRow(work)
                    }
                }
            }
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func workRow(_ work: WorkModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Title (Role) - Display only
                TextField("Title", text: Binding(
                    get: { work.scheduledNote ?? "" },
                    set: { _ in }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

                Spacer()

                // Status Picker - Display only
                Picker("Status", selection: Binding(
                    get: { work.status },
                    set: { _ in }
                )) {
                    Text("Active").tag(WorkStatus.active)
                    Text("Review").tag(WorkStatus.review)
                    Text("Complete").tag(WorkStatus.complete)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(true)

                // Due Date - Display only
                if let dueAt = work.dueAt {
                    DatePicker("Due", selection: .constant(dueAt), displayedComponents: .date)
                        .labelsHidden()
                        .disabled(true)
                } else {
                    Text("No due date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Linked Lesson display
            HStack(spacing: 8) {
                if let uuid = UUID(uuidString: work.lessonID), let l = lessonsByID[uuid] {
                    Text("Linked: \(l.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No lesson linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showLessonPickerForWork = work
                } label: {
                    Label("Change Lesson", systemImage: "book")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}
