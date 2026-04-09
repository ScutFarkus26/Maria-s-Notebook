// CommunicationDraftView.swift
// Sheet to draft a new parent communication: pick student, type, and template.

import SwiftUI
import CoreData

struct CommunicationDraftView: View {
    @Bindable var viewModel: ParentCommunicationViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStudent: CDStudent?
    @State private var selectedType: CommunicationType = .progressUpdate
    @State private var subject: String = ""
    @State private var messageBody: String = ""
    @State private var showingEditor = false

    var body: some View {
        Form {
            // Student picker
            Section("Student") {
                Picker("Student", selection: $selectedStudent) {
                    Text("Select a student…").tag(nil as CDStudent?)
                    ForEach(viewModel.students, id: \.id) { student in
                        Text(StudentFormatter.displayName(for: student))
                            .tag(student as CDStudent?)
                    }
                }
            }

            // Communication type
            Section("Type") {
                Picker("Type", selection: $selectedType) {
                    ForEach(CommunicationType.allCases) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            // Subject
            Section("Subject") {
                TextField("Subject line", text: $subject)
            }

            // Quick start options
            Section("Start From") {
                Button {
                    messageBody = templateBody(for: selectedType)
                    expandAndCreate()
                } label: {
                    Label("Use Default Template", systemImage: "doc.text")
                }
                .disabled(selectedStudent == nil)

                Button {
                    messageBody = ""
                    expandAndCreate()
                } label: {
                    Label("Start Blank", systemImage: "square.and.pencil")
                }
                .disabled(selectedStudent == nil)
            }
        }
        .navigationTitle("New Communication")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Actions

    private func expandAndCreate() {
        guard let student = selectedStudent else { return }

        if subject.isEmpty {
            subject = "\(selectedType.displayName) — \(StudentFormatter.displayName(for: student))"
        }

        let comm = viewModel.createDraft(
            student: student,
            type: selectedType,
            templateBody: messageBody,
            subject: subject,
            context: viewContext
        )
        _ = comm
        dismiss()
    }

    // MARK: - Default Templates

    private func templateBody(for type: CommunicationType) -> String {
        switch type {
        case .conference:
            return """
            Dear Family,

            Thank you for meeting with me about {{studentFirstName}}'s progress. Here is a summary of what we discussed:

            Academic Progress:


            Social-Emotional Development:


            Goals for the Coming Period:


            Please don't hesitate to reach out with any questions.

            Warm regards
            """
        case .progressUpdate:
            return """
            Dear Family,

            I wanted to share an update on {{studentFirstName}}'s recent progress in the classroom.

            Highlights:


            Areas of Growth:


            Looking forward to continued growth.

            Warm regards
            """
        case .concern:
            return """
            Dear Family,

            I'm reaching out regarding {{studentFirstName}} because I'd like to discuss something I've observed in the classroom.

            Observation:


            My Thoughts:


            Suggested Next Steps:


            I'd welcome the opportunity to discuss this further. Please let me know a good time to connect.

            Warm regards
            """
        case .introduction:
            return """
            Dear Family,

            Welcome! I'm excited to have {{studentFirstName}} in our classroom this year.

            A bit about our classroom:


            What to expect in the first few weeks:


            Please feel free to reach out anytime with questions or concerns.

            Warm regards
            """
        case .endOfYear:
            return """
            Dear Family,

            As we wrap up this school year, I wanted to share my reflections on {{studentFirstName}}'s growth.

            Key Accomplishments:


            Growth Areas:


            Summer Recommendations:


            It has been a wonderful year. Thank you for your partnership.

            Warm regards
            """
        case .custom:
            return ""
        }
    }
}
