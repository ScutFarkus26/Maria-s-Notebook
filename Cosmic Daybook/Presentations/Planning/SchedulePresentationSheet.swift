//
//  SchedulePresentationSheet.swift
//  Cosmic Daybook
//
//  Forming the group for a lesson — and saying so when some of the children
//  have already had it.
//
//  The sheet reads the presentation record once for this lesson, captions the
//  children who are on it, and if the guide plans one of them anyway it asks
//  the one question the notebook needs answered: is this a second pass or a
//  review. The answer travels back through `onPlan` and is written on the new
//  draft by `PresentationPlanner`, exactly as the MCP tools write it.
//

import SwiftUI
import CoreData

struct SchedulePresentationSheet: View {
    let lesson: CDLesson
    /// Children to start with selected — Today's ready queue preselects the
    /// ones it is proposing.
    var initialSelection: Set<UUID> = []
    let onPlan: (Set<UUID>, RepeatPurpose?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ])
    private var allStudentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled.
    // A child who has left the classroom is deliberately NOT filtered out here:
    // `StudentPickerModel` lists her disabled with the reason, which is the
    // whole point — a departure should be visible where the group is formed,
    // not a silent gap in the roster.
    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID, show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var studentSearchText: String = ""
    /// What the record says about this lesson, read once per lesson.
    @State private var recordIndex: PresentationRecordIndex?
    /// The same record, keyed by student id for the rows and chips.
    @State private var records: [UUID: PresentationRecordIndex.Given] = [:]
    /// How many of the selected children are already on record, while the
    /// second-pass/review question is up.
    @State private var repeatCount: Int?

    /// The rows the search leaves on screen.
    private var filteredRows: [StudentPickerRow] { rows(matching: studentSearchText) }

    /// Every child the sheet knows about, searched or not — what the ticked
    /// selection is judged against, so a child who has left can never be
    /// planned for just because the search hid her row.
    private var allRows: [StudentPickerRow] { rows(matching: "") }

    private func rows(matching search: String) -> [StudentPickerRow] {
        StudentPickerModel.rows(
            candidates: StudentPickerModel.candidates(allStudents),
            query: StudentPickerModel.Query(search: search, formerStudents: .shownBlocked),
            records: records
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                lessonHeader

                Divider()

                studentPicker

                Spacer()
            }
            .padding()
            .navigationTitle("Plan Presentation")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan") { attemptPlan() }
                        .disabled(selectedStudents.isEmpty)
                }
            }
        }
        .task(id: lesson.id) { loadRecord() }
        .confirmationDialog(
            repeatPromptTitle,
            isPresented: repeatPromptBinding,
            titleVisibility: .visible
        ) {
            Button("Plan a second pass") { complete(with: .secondPass) }
            Button("Plan a review") { complete(with: .review) }
            Button("Cancel", role: .cancel) { repeatCount = nil }
        } message: {
            Text("The new record says which of the two it is, and a second pass "
                + "flags their earlier record for re-teaching.")
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // MARK: - Pieces

    private var lessonHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan Presentation")
                .font(.headline)
            Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("This will add the presentation to your inbox")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var studentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Students")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !selectedStudentIDs.isEmpty {
                    Text("\(selectedStudentIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search students...", text: $studentSearchText)
                .textFieldStyle(.roundedBorder)

            if !selectedStudentIDs.isEmpty {
                selectedStudentChips
            }

            List {
                ForEach(filteredRows) { row in
                    studentRow(row)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 300)
        }
    }

    private var selectedStudentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedStudents, id: \.id) { student in
                    HStack(spacing: 4) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(.caption)
                        if let given = student.id.flatMap({ records[$0] }) {
                            StudentRecordCaption(given: given, compact: true)
                        }
                        Button {
                            if let studentID = student.id {
                                selectedStudentIDs.remove(studentID)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func studentRow(_ row: StudentPickerRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.candidate.displayName)
                    .foregroundStyle(row.isSelectable ? .primary : .secondary)
                rowCaption(row)
            }
            Spacer()
            if selectedStudentIDs.contains(row.id), row.isSelectable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStudentIDs = StudentPickerModel.toggling(
                row.id, in: selectedStudentIDs, rows: allRows
            )
        }
        .accessibilityHint(row.block?.shortReason ?? "")
        // Last, so the tap gesture above is inside the disabled subtree.
        .disabled(!row.isSelectable)
    }

    /// Why she cannot be planned for, or what the record already holds for her.
    @ViewBuilder
    private func rowCaption(_ row: StudentPickerRow) -> some View {
        if let block = row.block {
            Text(block.shortReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let given = row.record {
            StudentRecordCaption(given: given)
        }
    }

    // MARK: - The Record

    private func loadRecord() {
        if selectedStudentIDs.isEmpty, !initialSelection.isEmpty {
            selectedStudentIDs = initialSelection
        }
        guard let lessonID = lesson.id else {
            recordIndex = nil
            records = [:]
            return
        }
        let index = PresentationRecordIndex(lessonIDs: [lessonID.uuidString], in: viewContext)
        recordIndex = index
        records = StudentPickerModel.records(from: index, lesson: lessonID)
    }

    // MARK: - Planning

    private func attemptPlan() {
        guard let index = recordIndex else {
            complete(with: nil)
            return
        }
        let conflicts = PresentationPlanner.repeatConflicts(
            lesson: lesson, students: selectedStudents, index: index
        )
        if conflicts.isEmpty {
            complete(with: nil)
        } else {
            repeatCount = conflicts.count
        }
    }

    private func complete(with purpose: RepeatPurpose?) {
        repeatCount = nil
        onPlan(Set(selectedStudents.compactMap(\.id)), purpose)
        dismiss()
    }

    private var repeatPromptBinding: Binding<Bool> {
        Binding(
            get: { repeatCount != nil },
            set: { shown in if !shown { repeatCount = nil } }
        )
    }

    /// "2 of 3 already have this lesson".
    private var repeatPromptTitle: String {
        let count = repeatCount ?? 0
        let verb = count == 1 ? "has" : "have"
        return "\(count) of \(selectedStudents.count) already \(verb) this lesson"
    }

    /// The ticked children the sheet may actually plan for. A child who has
    /// left the classroom is filtered out here as well as blocked in the list,
    /// so nothing she was ticked for before she left reaches `onPlan`.
    private var selectedStudents: [CDStudent] {
        let plannable = Set(StudentPickerModel.selectableIDs(allRows))
        return allStudents.filter { student in
            guard let studentID = student.id else { return false }
            return selectedStudentIDs.contains(studentID) && plannable.contains(studentID)
        }
    }
}
