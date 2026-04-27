// ScheduleParshaLessonSheet.swift
// Pick students and an optional schedule date, then create a CDLessonAssignment
// for the given parsha lesson. The resulting assignment flows through the normal
// Presentations pipeline.

import SwiftUI
import CoreData

struct ScheduleParshaLessonSheet: View {
    let lesson: CDLesson
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true),
        NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)
    ])
    private var allStudentsRaw: FetchedResults<CDStudent>

    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var scheduleDate: Date = Date()
    @State private var includeDate: Bool = false

    private var allStudents: [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(allStudentsRaw).uniqueByID.filterEnrolled(),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    private var filteredStudents: [CDStudent] {
        let query = searchText.normalizedForComparison()
        guard !query.isEmpty else { return allStudents }
        return allStudents.filter { student in
            student.firstName.lowercased().contains(query) ||
            student.lastName.lowercased().contains(query) ||
            student.fullName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lesson") {
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(AppTheme.ScaledFont.bodySemibold)
                    if let parshaKey = lesson.parshaKey, !parshaKey.isEmpty {
                        Text(HebrewParshaService.displayName(forKey: parshaKey))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Schedule for a date", isOn: $includeDate)
                    if includeDate {
                        DatePicker("Date", selection: $scheduleDate, displayedComponents: [.date])
                    } else {
                        Text("Will be added to your inbox as a draft.")
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("When")
                }

                Section {
                    TextField("Search students\u{2026}", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ForEach(filteredStudents, id: \.id) { student in
                        HStack {
                            Text(StudentFormatter.displayName(for: student))
                            Spacer()
                            if let studentID = student.id, selectedStudentIDs.contains(studentID) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(student)
                        }
                    }
                } header: {
                    HStack {
                        Text("Students")
                        Spacer()
                        if !selectedStudentIDs.isEmpty {
                            Text("\(selectedStudentIDs.count) selected")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add to Presentations")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addToPresentations()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedStudentIDs.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private func toggle(_ student: CDStudent) {
        guard let id = student.id else { return }
        if selectedStudentIDs.contains(id) {
            selectedStudentIDs.remove(id)
        } else {
            selectedStudentIDs.insert(id)
        }
    }

    private func addToPresentations() {
        guard lesson.id != nil else { return }
        let students: [CDStudent] = allStudents.filter { student in
            guard let id = student.id else { return false }
            return selectedStudentIDs.contains(id)
        }

        if includeDate {
            _ = PresentationFactory.makeScheduled(
                lesson: lesson,
                students: students,
                scheduledFor: scheduleDate,
                context: viewContext
            )
        } else {
            _ = PresentationFactory.makeDraft(
                lesson: lesson,
                students: students,
                context: viewContext
            )
        }

        saveCoordinator.save(viewContext, reason: "Schedule parsha lesson")
        onDone()
        dismiss()
    }
}
