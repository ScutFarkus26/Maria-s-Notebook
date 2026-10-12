// GuardianEditSheet.swift
// Add/edit form for a student's parent/guardian contact.

import SwiftUI
import CoreData

struct GuardianEditSheet: View {
    let studentID: String
    /// Nil when adding a new guardian.
    let guardian: CDGuardian?

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var relationship: GuardianRelationship = .parent
    @State private var receivesReports = true
    @State private var notes = ""
    @State private var showingDeleteConfirmation = false

    private var isNew: Bool { guardian == nil }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        (!trimmedName.isEmpty || !trimmedEmail.isEmpty) && Self.emailProblem(email) == nil
    }

    /// What's wrong with the typed email, in a plain sentence; nil when it's
    /// one address or empty. Two addresses in the field went to Mail as one
    /// broken recipient (2026-10-11 #77).
    static func emailProblem(_ text: String) -> String? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        let check = AttendanceEmail.checkRecipients(typed)
        if check.addresses.count > 1 { return AppErrorMessages.ParentReports.guardianOneAddress }
        if check.addresses.count == 1, check.leftOut.isEmpty { return nil }
        return AppErrorMessages.ParentReports.guardianNotAnAddress
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Picker("Relationship", selection: $relationship) {
                        ForEach(GuardianRelationship.allCases) { relationship in
                            Text(relationship.displayName).tag(relationship)
                        }
                    }
                } header: {
                    Text("Contact")
                } footer: {
                    if let problem = Self.emailProblem(email) {
                        Text(problem)
                            .foregroundStyle(AppColors.warning)
                    }
                }
                Section {
                    Toggle("Receives progress reports", isOn: $receivesReports)
                } footer: {
                    Text("Monthly progress reports are addressed to guardians with this turned on.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if !isNew {
                    Section {
                        Button("Delete Contact", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Add Guardian" : "Edit Guardian")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this contact?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteGuardian() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: loadDraft)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func loadDraft() {
        guard let guardian else { return }
        name = guardian.name
        email = guardian.email
        relationship = guardian.relationship
        receivesReports = guardian.receivesReports
        notes = guardian.notes
    }

    private func save() {
        let target: CDGuardian
        if let guardian {
            target = guardian
        } else {
            target = CDGuardian(context: viewContext)
            target.studentID = studentID
            let request = CDGuardian.fetchRequest(studentID: studentID)
            let siblingCount = (try? viewContext.count(for: request)) ?? 0
            target.sortOrder = Int64(siblingCount)
        }
        target.name = trimmedName
        target.email = trimmedEmail
        target.relationship = relationship
        target.receivesReports = receivesReports
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.modifiedAt = Date()
        viewContext.safeSave()
        dismiss()
    }

    private func deleteGuardian() {
        guard let guardian else { return }
        viewContext.delete(guardian)
        viewContext.safeSave()
        dismiss()
    }
}
