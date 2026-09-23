// OrderRequestSettingsView.swift
// Who order requests go to. Shown in Settings › Communication and from the
// Orders screen's toolbar; the values sync across devices.

import SwiftUI

struct OrderRequestSettingsView: View {
    @SyncedAppStorage(OrderRequestPrefs.recipientNameKey) private var recipientName: String = ""
    @SyncedAppStorage(OrderRequestPrefs.recipientEmailKey) private var recipientEmail: String = ""
    @SyncedAppStorage(OrderRequestPrefs.signOffNameKey) private var signOffName: String = ""

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
            TextField("Sign off as (your name)", text: $signOffName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            #endif

            Text("The request email opens with \u{201C}Hi \(greetingName),\u{201D} and is addressed to "
                 + "this email. Separate several addresses with commas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: recipientName) { _, _ in SettingsCategory.markModified(.communication) }
        .onChange(of: recipientEmail) { _, _ in SettingsCategory.markModified(.communication) }
        .onChange(of: signOffName) { _, _ in SettingsCategory.markModified(.communication) }
    }

    private var greetingName: String {
        let name = recipientName.trimmed()
        return name.isEmpty ? "…" : name
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
        .frame(minWidth: 480, minHeight: 240)
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
