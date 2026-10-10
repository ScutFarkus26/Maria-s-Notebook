// OrderRequestSettingsView.swift
// Who order requests go to, who's copied, and the message's wording. Shown in
// Settings › Communication and from the Orders screen's toolbar; the values
// sync across devices.

import SwiftUI

struct OrderRequestSettingsView: View {
    @SyncedAppStorage(OrderRequestPrefs.recipientNameKey) private var recipientName: String = ""
    @SyncedAppStorage(OrderRequestPrefs.recipientEmailKey) private var recipientEmail: String = ""
    @SyncedAppStorage(OrderRequestPrefs.signOffNameKey) private var signOffName: String = ""
    @SyncedAppStorage(OrderRequestPrefs.ccEmailKey) private var ccEmail: String = ""
    @SyncedAppStorage(OrderRequestPrefs.messageTemplateKey) private var messageTemplate: String = ""

    /// Off in the request sheet, which has its own message editor.
    var showsMessage = true

    var body: some View {
        // A plain stack, not a Form: this is embedded inline in a SettingsGroup
        // inside the settings ScrollView, where a nested Form scrolls its own
        // content out of reach.
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            LabeledContent("Send requests to") {
                TextField("Name", text: $recipientName, prompt: Text("Ms. Rivera"))
                    .frame(minWidth: 260)
            }
            LabeledContent("Their email") {
                emailField
                    .frame(minWidth: 260)
            }
            LabeledContent("CC") {
                ccField
                    .frame(minWidth: 260)
            }
            LabeledContent("Sign off as") {
                TextField("Your name", text: $signOffName, prompt: Text("Your name"))
                    .frame(minWidth: 260)
            }
            #else
            TextField("Send requests to (name)", text: $recipientName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            emailField
                .textFieldStyle(.roundedBorder)
            ccField
                .textFieldStyle(.roundedBorder)
            TextField("Sign off as (your name)", text: $signOffName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            #endif

            Text("The request email goes to this email, with the CC addresses copied. "
                 + "Separate several addresses with commas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Array(leftOutNotes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if showsMessage {
                messageEditor
            }
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)
                .padding(.top, 8)
            TextEditor(text: templateBinding)
                .font(.body)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            Text("\(OrderRequestMessage.Placeholder.name) becomes \(greetingName), "
                 + "\(OrderRequestMessage.Placeholder.items) becomes the list of items, and "
                 + "\(OrderRequestMessage.Placeholder.signOff) becomes your sign-off. "
                 + "You can still change the wording of each email before you send it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !messageTemplate.trimmed().isEmpty {
                Button("Use the Standard Message") { messageTemplate = "" }
            }
        }
    }

    /// Shows the standard message until the guide changes it; saving the
    /// standard text back stores nothing, so it keeps its "this"/"these".
    private var templateBinding: Binding<String> {
        Binding(
            get: { messageTemplate.isEmpty ? OrderRequestMessage.standardTemplate : messageTemplate },
            set: { newValue in
                messageTemplate = newValue.trimmed() == OrderRequestMessage.standardTemplate.trimmed()
                    ? "" : newValue
            }
        )
    }

    /// Which typed entries aren't addresses and get no email, for the email
    /// field and then CC.
    private var leftOutNotes: [String] {
        [recipientEmail, ccEmail].compactMap(AttendanceEmail.leftOutNote(for:))
    }

    private var greetingName: String {
        let name = recipientName.trimmed()
        return name.isEmpty ? "their name" : name
    }

    private var ccField: some View {
        TextField("CC (optional)", text: $ccEmail, prompt: Text("principal@school.org, admin@school.org"))
            .autocorrectionDisabled(true)
            #if os(iOS)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            #endif
    }

    private var emailField: some View {
        TextField("Email address", text: $recipientEmail, prompt: Text("office@school.org"))
            .autocorrectionDisabled(true)
            #if os(iOS)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            #endif
    }
}

/// The same settings as a sheet, for the Orders screen's toolbar.
struct OrderRequestSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                OrderRequestSettingsView()
                    .padding(20)
            }
            .navigationTitle("Order Requests")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct OrderRequestSettingsViewPreview: View {
    var body: some View {
        OrderRequestSettingsView()
            .padding()
    }
}

#Preview {
    OrderRequestSettingsViewPreview()
}
