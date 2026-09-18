// ClassCurriculumRowSheet.swift
// One row of the class map, opened: the children in each state, and — for a
// single lesson — a button that makes a draft presentation for everyone who
// has not had it yet. The set of names the spec wanted to hand straight to
// schedule_presentation, in the app.

import SwiftUI

struct ClassCurriculumRowSheet: View {
    let row: ClassRow
    let model: ClassCurriculumMapModel
    let onPlan: (UUID, [CurriculumStudentRef]) -> Void
    let onClose: () -> Void

    @State private var selected: Set<UUID> = []

    private var notPresented: [CurriculumStudentRef] { model.students(in: .notPresented, on: row) }

    var body: some View {
        NavigationStack {
            List {
                if let lessonID = row.lessonID, !notPresented.isEmpty {
                    planSection(lessonID: lessonID)
                }
                ForEach(CurriculumCellState.allCases.reversed(), id: \.rawValue) { state in
                    stateSection(state)
                }
            }
            .navigationTitle(row.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }

    private func planSection(lessonID: UUID) -> some View {
        Section {
            Button {
                let chosen: [CurriculumStudentRef] = notPresented.filter { selected.contains($0.id) }
                onPlan(lessonID, chosen.isEmpty ? notPresented : chosen)
            } label: {
                Label(planLabel, systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
        } footer: {
            Text("Tick names to plan for some of them; with nothing ticked, the whole set goes on the draft.")
        }
    }

    @ViewBuilder
    private func stateSection(_ state: CurriculumCellState) -> some View {
        let students: [CurriculumStudentRef] = model.students(in: state, on: row)
        if !students.isEmpty {
            let selectable: Bool = state == .notPresented && row.lessonID != nil
            Section("\(state.label) (\(students.count))") {
                ForEach(students) { student in
                    studentRow(student, selectable: selectable)
                }
            }
        }
    }

    private var planLabel: String {
        let count = selected.isEmpty ? notPresented.count : selected.count
        return "Plan a presentation for \(count) child\(count == 1 ? "" : "ren")"
    }

    private func studentRow(_ student: CurriculumStudentRef, selectable: Bool) -> some View {
        HStack {
            if selectable {
                Image(systemName: selected.contains(student.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(student.id) ? Color.accentColor : Color.secondary)
            }
            Text(student.fullName)
            Spacer()
            Text(model.columns.first { $0.id == student.id }?.badge ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectable else { return }
            if selected.contains(student.id) { selected.remove(student.id) } else { selected.insert(student.id) }
        }
        .accessibilityAddTraits(selectable ? .isButton : [])
    }
}
