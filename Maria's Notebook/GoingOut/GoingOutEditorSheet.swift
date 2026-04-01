// GoingOutEditorSheet.swift
// Create/edit sheet for Going-Out records.

import SwiftUI
import CoreData

struct GoingOutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext

    let existingGoingOut: CDGoingOut?
    let onSave: (CDGoingOut) -> Void

    @State private var title: String = ""
    @State private var purpose: String = ""
    @State private var destination: String = ""
    @State private var proposedDate: Date = Date()
    @State private var hasDate: Bool = false
    @State private var selectedStudentIDs: Set<UUID> = []

    @FetchRequest(sortDescriptors: CDStudent.sortByName)
    private var allStudents: FetchedResults<CDStudent>

    private var visibleStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(Array(allStudents).filter(\.isEnrolled))
    }

    init(existingGoingOut: CDGoingOut? = nil, onSave: @escaping (CDGoingOut) -> Void) {
        self.existingGoingOut = existingGoingOut
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Purpose", text: $purpose, axis: .vertical)
                        .lineLimit(3)
                    TextField("Destination", text: $destination)
                }

                // Date
                Section("Date") {
                    Toggle("Set proposed date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Proposed Date", selection: $proposedDate, displayedComponents: .date)
                    }
                }

                // Students
                Section("Students") {
                    ForEach(visibleStudents, id: \.objectID) { student in
                        Button {
                            guard let studentID = student.id else { return }
                            if selectedStudentIDs.contains(studentID) {
                                selectedStudentIDs.remove(studentID)
                            } else {
                                selectedStudentIDs.insert(studentID)
                            }
                        } label: {
                            HStack {
                                Text("\(student.firstName.prefix(1))\(student.lastName.prefix(1))")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(AppColors.color(forLevel: student.level).gradient, in: Circle())

                                Text("\(student.firstName) \(student.lastName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if let studentID = student.id, selectedStudentIDs.contains(studentID) {
                                    Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(existingGoingOut == nil ? "New Going-Out" : "Edit Going-Out")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmed().isEmpty)
                }
            }
            .onAppear {
                if let existing = existingGoingOut {
                    title = existing.title
                    purpose = existing.purpose
                    destination = existing.destination
                    if let date = existing.proposedDate {
                        proposedDate = date
                        hasDate = true
                    }
                    selectedStudentIDs = Set(existing.studentUUIDs)
                }
            }
        }
    }

    private func save() {
        let goingOut: CDGoingOut
        if let existing = existingGoingOut {
            goingOut = existing
            goingOut.title = title
            goingOut.purpose = purpose
            goingOut.destination = destination
            goingOut.proposedDate = hasDate ? proposedDate : nil
            goingOut.studentUUIDs = Array(selectedStudentIDs)
            goingOut.modifiedAt = Date()
        } else {
            goingOut = CDGoingOut(context: modelContext)
            goingOut.title = title
            goingOut.purpose = purpose
            goingOut.destination = destination
            goingOut.proposedDate = hasDate ? proposedDate : nil
            goingOut.studentUUIDs = Array(selectedStudentIDs)
        }
        modelContext.safeSave()
        onSave(goingOut)
        dismiss()
    }
}
