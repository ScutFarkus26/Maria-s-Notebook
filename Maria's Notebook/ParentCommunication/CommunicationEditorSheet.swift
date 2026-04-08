// CommunicationEditorSheet.swift
// Editor for viewing and editing a parent communication draft, with share/send actions.

import SwiftUI

struct CommunicationEditorSheet: View {
    @ObservedObject var communication: CDParentCommunication
    @Bindable var viewModel: ParentCommunicationViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String = ""
    @State private var messageBody: String = ""
    @State private var notes: String = ""
    @State private var showingSendConfirmation = false

    var body: some View {
        Form {
            // Header info
            Section {
                HStack {
                    Text("Student")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.studentName(for: communication))
                }

                HStack {
                    Text("Type")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(communication.communicationType.displayName,
                          systemImage: communication.communicationType.icon)
                    .foregroundStyle(communication.communicationType.color)
                    .font(.subheadline)
                }

                if let date = communication.createdAt {
                    HStack {
                        Text("Created")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Subject
            Section("Subject") {
                TextField("Subject line", text: $subject)
            }

            // Body
            Section("Message") {
                TextEditor(text: $messageBody)
                    .frame(minHeight: 200)
            }

            // Internal notes
            Section("Internal Notes") {
                TextField("Notes (not shared with parents)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Actions
            Section {
                if communication.isDraft {
                    Button {
                        showingSendConfirmation = true
                    } label: {
                        Label("Mark as Sent", systemImage: "paperplane.fill")
                    }
                } else if let sentAt = communication.sentAt {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Sent \(sentAt, format: .dateTime.month(.abbreviated).day().year())")
                            .foregroundStyle(.secondary)
                    }
                }

                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            if communication.isDraft {
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteCommunication(communication, context: viewContext)
                        dismiss()
                    } label: {
                        Label("Delete Draft", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(communication.isDraft ? "Edit Draft" : "View Communication")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    save()
                    dismiss()
                }
            }
        }
        .onAppear {
            subject = communication.subject
            messageBody = communication.body
            notes = communication.notes
        }
        .alert("Mark as Sent", isPresented: $showingSendConfirmation) {
            Button("Mark Sent") {
                save()
                viewModel.markAsSent(communication, context: viewContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will move the communication to the Sent tab. You can still view it there.")
        }
    }

    // MARK: - Helpers

    private var shareText: String {
        var text = ""
        if !subject.isEmpty {
            text += "Subject: \(subject)\n\n"
        }
        text += messageBody
        return text
    }

    private func save() {
        communication.subject = subject
        communication.body = messageBody
        communication.notes = notes
        communication.modifiedAt = Date()
        viewContext.safeSave()
    }
}
